Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.RecoveryServices -ErrorAction Stop # Note that this contains TimeZoneConverter
Import-Module Az.Resources -ErrorAction Stop
Import-Module $PSScriptRoot/AzureNetwork -ErrorAction Stop
Import-Module $PSScriptRoot/Cryptography -ErrorAction Stop
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Get root directory for configuration files
# ------------------------------------------
function Get-ConfigRootDir {
    try {
        return Join-Path (Get-Item $PSScriptRoot).Parent.Parent.FullName "environment_configs" -Resolve -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        Add-LogMessage -Level Fatal "Could not find the configuration file root directory!"
    }
}


# Load minimal management config parameters from JSON config file into a hashtable
# --------------------------------------------------------------------------------
function Get-CoreConfig {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
        [string]$shmId,
        [Parameter(Mandatory = $false, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
        [string]$sreId = $null
    )
    # Construct filename for this config file
    if ($sreId) {
        $configFilename = "sre_${shmId}${sreId}_core_config.json"
    } else {
        $configFilename = "shm_${shmId}_core_config.json"
    }
    # Try to load the file
    try {
        $configPath = Join-Path $(Get-ConfigRootDir) $configFilename -Resolve -ErrorAction Stop
        $configJson = Get-Content -Path $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        Add-LogMessage -Level Fatal "Could not find a config file named '$configFilename'..."
    } catch [System.ArgumentException] {
        Add-LogMessage -Level Fatal "'$configPath' is not a valid JSON config file..."
    }
    # Ensure that naming structure is being adhered to
    if ($sreId -and ($sreId -ne $configJson.sreId)) {
        Add-LogMessage -Level Fatal "Config file '$configFilename' has an incorrect SRE ID: $($configJson.sreId)!"
    }
    if ($shmId -ne $configJson.shmId) {
        Add-LogMessage -Level Fatal "Config file '$configFilename' has an incorrect SHM ID: $($configJson.shmId)!"
    }
    return $configJson
}


# Get SHM configuration
# ---------------------
function Get-ShmConfig {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
        $shmId
    )
    # Import minimal management config parameters from JSON config file - we can derive the rest from these
    $shmConfigBase = Get-CoreConfig -shmId $shmId

    # Ensure the name in the config is < 27 characters excluding spaces
    if ($shmConfigBase.name.Replace(" ", "").Length -gt 27) {
        Add-LogMessage -Level Fatal "The 'name' entry in the core SHM config must have fewer than 27 characters (excluding spaces)."
    }

    # Safe Haven management config
    # ----------------------------
    $shm = [ordered]@{
        azureAdminGroupName = $shmConfigBase.azure.adminGroupName
        id                  = $shmConfigBase.shmId
        location            = $shmConfigBase.azure.location
        name                = $shmConfigBase.name
        organisation        = $shmConfigBase.organisation
        rgPrefix            = $shmConfigBase.overrides.rgPrefix ? $shmConfigBase.overrides.rgPrefix : "RG_SHM_$($shmConfigBase.shmId)".ToUpper()
        nsgPrefix           = $shmConfigBase.overrides.nsgPrefix ? $shmConfigBase.overrides.nsgPrefix : "NSG_SHM_$($shmConfigBase.shmId)".ToUpper()
        subscriptionName    = $shmConfigBase.azure.subscriptionName
        vmImagesRgPrefix    = $shmConfigBase.vmImages.rgPrefix ? $shmConfigBase.vmImages.rgPrefix : "RG_VMIMAGES"
        storageTypeDefault  = "Standard_GRS"
        diskTypeDefault     = "Standard_LRS"
}
    # For normal usage this does not need to be user-configurable.
    # However, if you are migrating an existing SHM you will need to ensure that the address spaces of the SHMs do not overlap
    $shmIpPrefix = $shmConfigBase.overrides.ipPrefix ? $shmConfigBase.overrides.ipPrefix : "10.0.0"

    # Set timezone and NTP configuration
    # Google is one of the few NTP services to provide an exhaustive, stable list of IP addresses.
    # However, note that the Google NTP servers are incompatible with others due to leap-second smearing
    # --------------------------------------------------------------------------------------------------
    $timezoneLinux = $shmConfigBase.timezone ? $shmConfigBase.timezone : "Europe/London"
    $shm.time = [ordered]@{
        timezone = [ordered]@{
            linux   = $timezoneLinux
            windows = [TimeZoneConverter.TZConvert]::IanaToWindows($timezoneLinux)
        }
        ntp      = [ordered]@{
            serverAddresses = @("216.239.35.0", "216.239.35.4", "216.239.35.8", "216.239.35.12")
            serverFqdns     = @("time.google.com", "time1.google.com", "time2.google.com", "time3.google.com", "time4.google.com")
        }
    }

    # SRD build images
    # ----------------
    $vmImagesSubscriptionName = $shmConfigBase.vmImages.subscriptionName ? $shmConfigBase.vmImages.subscriptionName : $shm.subscriptionName
    $vmImagesLocation = $shmConfigBase.vmImages.location ? $shmConfigBase.vmImages.location : $shm.location
    # Since an ImageGallery cannot be moved once created, we must ensure that the location parameter matches any gallery that already exists
    $originalContext = Get-AzContext
    if ($originalContext) {
        $null = Set-AzContext -SubscriptionId $vmImagesSubscriptionName -ErrorAction Stop
        $locations = Get-AzResource | Where-Object { $_.ResourceGroupName -like "$($shm.vmImagesRgPrefix)_*" } | ForEach-Object { $_.Location } | Sort-Object | Get-Unique
        if ($locations.Count -gt 1) {
            Add-LogMessage -Level Fatal "Image building resources found in multiple locations: ${locations}!"
        } elseif ($locations.Count -eq 1) {
            if ($vmImagesLocation -ne $locations) {
                Add-LogMessage -Level Fatal "Image building location ($vmImagesLocation) must be set to ${locations}!"
            }
        }
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    } else {
        Add-LogMessage -Level Warning "Skipping check for image building location as you are not logged in to Azure! Run Connect-AzAccount to log in."
    }
    # Construct build images config
    $srdImageStorageSuffix = New-RandomLetters -SeedPhrase $vmImagesSubscriptionName
    $shm.srdImage = [ordered]@{
        subscription    = $vmImagesSubscriptionName
        location        = $vmImagesLocation
        bootdiagnostics = [ordered]@{
            rg          = "$($shm.vmImagesRgPrefix)_BOOT_DIAGNOSTICS"
            accountName = "vmimagesbootdiag${srdImageStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
        }
        build           = [ordered]@{
            rg     = "$($shm.vmImagesRgPrefix)_BUILD_CANDIDATES"
            nsg    = [ordered]@{
                name               = "NSG_VMIMAGES_BUILD_CANDIDATES"
                allowedIpAddresses = $shmConfigbase.vmImages.buildIpAddresses ? @($shmConfigbase.vmImages.buildIpAddresses) : @("193.60.220.240", "193.60.220.253")
                rules              = "vmimages-nsg-rules-build-candidates.json"
            }
            vnet   = [ordered]@{
                name = "VNET_VMIMAGES"
                cidr = "10.48.0.0/16"
            }
            subnet = [ordered]@{
                name = "BuildCandidatesSubnet"
                cidr = "10.48.0.0/24"
            }
            # Installation of R packages (and some Python builds) is parallelisable
            # We want a compute-optimised VM, since per-core performance is the bottleneck
            # Standard_E2_v3  => 2 cores; 16GB RAM; 2.3 GHz; £0.1163/hr
            # Standard_F4s_v2 => 4 cores;  8GB RAM; 3.7 GHz; £0.1506/hr
            # Standard_D4_v3  => 4 cores; 16GB RAM; 2.4 GHz; £0.1730/hr
            # Standard_E4_v3  => 4 cores; 32GB RAM; 2.3 GHz; £0.2326/hr
            # Standard_F8s_v2 => 8 cores; 16GB RAM; 3.7 GHz; £0.3012/hr
            # Standard_H8     => 8 cores; 56GB RAM; 3.6 GHz; £0.4271/hr
            # Standard_E8_v3  => 8 cores; 64GB RAM; 2.3 GHz; £0.4651/hr
            vm     = [ordered]@{
                diskSizeGb = 128
                diskType   = $shm.diskTypeDefault
                size       = "Standard_F8s_v2"
            }
        }
        gallery         = [ordered]@{
            rg   = "$($shm.vmImagesRgPrefix)_GALLERY"
            name = "DATA_SAFE_HAVEN_SHARED_IMAGES"
        }
        images          = [ordered]@{
            rg = "$($shm.vmImagesRgPrefix)_STORAGE"
        }
        keyVault        = [ordered]@{
            rg   = "$($shm.vmImagesRgPrefix)_SECRETS"
            name = "kv-shm-$($shm.id)-images".ToLower() | Limit-StringLength -MaximumLength 24
        }
        network         = [ordered]@{
            rg = "$($shm.vmImagesRgPrefix)_NETWORKING"
        }
    }

    # Domain config
    # -------------
    $shm.domain = [ordered]@{
        fqdn        = $shmConfigBase.domain
        netbiosName = ($shmConfigBase.netbiosName ? $shmConfigBase.netbiosName : $shm.id).ToUpper() | Limit-StringLength -MaximumLength 15 -FailureIsFatal
        dn          = "DC=$(($shmConfigBase.domain).Replace('.',',DC='))"
        ous         = [ordered]@{
            databaseServers   = [ordered]@{ name = "Secure Research Environment Database Servers" }
            linuxServers      = [ordered]@{ name = "Secure Research Environment Linux Servers" }
            rdsGatewayServers = [ordered]@{ name = "Secure Research Environment RDS Gateway Servers" }
            rdsSessionServers = [ordered]@{ name = "Secure Research Environment RDS Session Servers" }
            researchUsers     = [ordered]@{ name = "Safe Haven Research Users" }
            securityGroups    = [ordered]@{ name = "Safe Haven Security Groups" }
            serviceAccounts   = [ordered]@{ name = "Safe Haven Service Accounts" }
            identityServers   = [ordered]@{ name = "Safe Haven Identity Servers" }
        }
    }
    $shm.domain.fqdnLower = ($shm.domain.fqdn).ToLower()
    $shm.domain.fqdnUpper = ($shm.domain.fqdn).ToUpper()
    foreach ($ouName in $shm.domain.ous.Keys) {
        $shm.domain.ous[$ouName].path = "OU=$($shm.domain.ous[$ouName].name),$($shm.domain.dn)"
    }
    # Security groups
    $shm.domain.securityGroups = [ordered]@{
        computerManagers = [ordered]@{ name = "SG Safe Haven Computer Management Users" }
        serverAdmins     = [ordered]@{ name = "SG Safe Haven Server Administrators" }
    }
    foreach ($groupName in $shm.domain.securityGroups.Keys) {
        $shm.domain.securityGroups[$groupName].description = $shm.domain.securityGroups[$groupName].name
    }

    # Network config
    # --------------
    # Deconstruct base address prefix to allow easy construction of IP based parameters
    $shmPrefixOctets = $shmIpPrefix.Split(".")
    $shmBasePrefix = "$($shmPrefixOctets[0]).$($shmPrefixOctets[1])"
    $shmThirdOctet = ([int]$shmPrefixOctets[2])
    $shm.network = [ordered]@{
        vnet = [ordered]@{
            name    = "VNET_SHM_$($shm.id)".ToUpper()
            cidr    = "${shmBasePrefix}.${shmThirdOctet}.0/21"
            rg      = "$($shm.rgPrefix)_NETWORKING".ToUpper()
            subnets = [ordered]@{
                identity      = [ordered]@{
                    name = "IdentitySubnet"
                    cidr = "${shmBasePrefix}.${shmThirdOctet}.0/24"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_IDENTITY".ToUpper()
                        rules = "shm-nsg-rules-identity.json"
                    }
                }
                monitoring    = [ordered]@{
                    name = "MonitoringSubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 1).0/24"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_MONITORING".ToUpper()
                        rules = "shm-nsg-rules-monitoring.json"
                    }
                }
                firewall      = [ordered]@{
                    # NB. The firewall subnet MUST be named 'AzureFirewallSubnet'. See https://docs.microsoft.com/en-us/azure/firewall/tutorial-firewall-deploy-portal
                    name = "AzureFirewallSubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 2).0/24"
                }
                updateServers = [ordered]@{
                    name = "UpdateServersSubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 3).0/24"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_UPDATE_SERVERS".ToUpper()
                        rules = "shm-nsg-rules-update-servers.json"
                    }
                }
                gateway       = [ordered]@{
                    # NB. The Gateway subnet MUST be named 'GatewaySubnet'. See https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq#do-i-need-a-gatewaysubnet
                    name = "GatewaySubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 7).0/24"
                }
            }
        }
        vpn  = [ordered]@{
            cidr = "172.16.201.0/24" # NB. this must not overlap with the VNet that the VPN gateway is part of
        }
    }
    foreach ($tier in @(2, 3)) {
        $shmRepositoryPrefix = "10.10.${tier}"
        $shm.network["vnetRepositoriesTier${tier}"] = [ordered]@{
            name    = "VNET_SHM_$($shm.id)_PACKAGE_REPOSITORIES_TIER_${tier}".ToUpper()
            cidr    = "${shmRepositoryPrefix}.0/24"
            rg      = $shm.network.vnet.rg
            subnets = [ordered]@{
                deployment      = [ordered]@{
                    name = "RepositoryDeploymentSubnet"
                    cidr = "${shmRepositoryPrefix}.0/26"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_REPOSITORY_DEPLOYMENT_TIER_${tier}".ToUpper()
                        rules = "shm-nsg-rules-repository-deployment-tier${tier}.json"
                    }
                }
                mirrorsExternal = [ordered]@{
                    name = "RepositoryMirrorsExternalTier${tier}Subnet"
                    cidr = "${shmRepositoryPrefix}.64/26"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_REPOSITORY_MIRRORS_EXTERNAL_TIER${tier}".ToUpper()
                        rules = "shm-nsg-rules-repository-mirrors-external-tier${tier}.json"
                    }
                }
                mirrorsInternal = [ordered]@{
                    name = "RepositoryMirrorsInternalTier${tier}Subnet"
                    cidr = "${shmRepositoryPrefix}.128/26"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_REPOSITORY_MIRRORS_INTERNAL_TIER${tier}".ToUpper()
                        rules = "shm-nsg-rules-repository-mirrors-internal-tier${tier}.json"
                    }
                }
                proxies         = [ordered]@{
                    name = "RepositoryProxiesTier${tier}Subnet"
                    cidr = "${shmRepositoryPrefix}.192/26"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_REPOSITORY_PROXIES_TIER_${tier}".ToUpper()
                        rules = "shm-nsg-rules-repository-proxies-tier${tier}.json"
                    }
                }
            }
        }
    }

    # Monitoring config
    # -----------------
    # All Microsoft public IP addresses from https://www.microsoft.com/en-us/download/confirmation.aspx?id=53602
    $microsoftIpAddresses = @("4.128.0.0/12", "4.144.0.0/12", "4.160.0.0/12", "4.176.0.0/12", "4.192.0.0/12", "4.208.0.0/12", "4.224.0.0/12", "4.240.0.0/12", "13.64.0.0/11", "13.96.0.0/13", "13.104.0.0/14", "20.0.0.0/11", "20.33.0.0/16", "20.34.0.0/15", "20.36.0.0/14", "20.40.0.0/13", "20.48.0.0/12", "20.64.0.0/10", "20.128.0.0/16", "20.130.0.0/16", "20.135.0.0/16", "20.136.0.0/16", "20.140.0.0/15", "20.143.0.0/16", "20.144.0.0/14", "20.150.0.0/15", "20.152.0.0/16", "20.153.0.0/16", "20.157.0.0/16", "20.158.0.0/15", "20.160.0.0/12", "20.176.0.0/14", "20.180.0.0/14", "20.184.0.0/13", "20.192.0.0/10", "23.96.0.0/13", "40.64.0.0/10", "40.162.0.0/16", "42.159.0.0/16", "51.4.0.0/15", "51.8.0.0/16", "51.10.0.0/15", "51.12.0.0/15", "51.18.0.0/16", "51.51.0.0/16", "51.53.0.0/16", "51.103.0.0/16", "51.104.0.0/15", "51.107.0.0/16", "51.116.0.0/16", "51.120.0.0/16", "51.124.0.0/16", "51.132.0.0/16", "51.136.0.0/15", "51.138.0.0/16", "51.140.0.0/14", "51.144.0.0/15", "52.96.0.0/12", "52.112.0.0/14", "52.120.0.0/14", "52.125.0.0/16", "52.126.0.0/15", "52.130.0.0/15", "52.132.0.0/14", "52.136.0.0/13", "52.145.0.0/16", "52.146.0.0/15", "52.148.0.0/14", "52.152.0.0/13", "52.160.0.0/11", "52.224.0.0/11", "64.4.0.0/18", "65.52.0.0/14", "66.119.144.0/20", "68.18.0.0/15", "68.154.0.0/15", "68.210.0.0/15", "68.218.0.0/15", "68.220.0.0/15", "70.37.0.0/17", "70.37.128.0/18", "70.152.0.0/15", "70.156.0.0/15", "72.144.0.0/14", "72.152.0.0/14", "74.160.0.0/14", "74.176.0.0/14", "74.224.0.0/14", "74.234.0.0/15", "74.240.0.0/14", "74.248.0.0/15", "91.190.216.0/21", "94.245.64.0/18", "98.64.0.0/14", "98.70.0.0/15", "102.37.0.0/16", "102.133.0.0/16", "103.9.8.0/22", "103.25.156.0/24", "103.25.157.0/24", "103.25.158.0/23", "103.36.96.0/22", "103.255.140.0/22", "104.40.0.0/13", "104.146.0.0/15", "104.208.0.0/13", "108.140.0.0/14", "111.221.16.0/20", "111.221.64.0/18", "128.94.0.0/16", "129.75.0.0/16", "131.107.0.0/16", "131.253.1.0/24", "131.253.3.0/24", "131.253.5.0/24", "131.253.6.0/24", "131.253.8.0/24", "131.253.12.0/22", "131.253.16.0/23", "131.253.18.0/24", "131.253.21.0/24", "131.253.22.0/23", "131.253.24.0/21", "131.253.32.0/20", "131.253.61.0/24", "131.253.62.0/23", "131.253.64.0/18", "131.253.128.0/17", "132.164.0.0/16", "132.245.0.0/16", "134.170.0.0/16", "134.177.0.0/16", "135.130.0.0/16", "135.149.0.0/16", "137.116.0.0/15", "137.135.0.0/16", "138.91.0.0/16", "138.105.0.0/16", "138.196.0.0/16", "138.239.0.0/16", "139.217.0.0/16", "139.219.0.0/16", "141.251.0.0/16", "143.64.0.0/16", "146.147.0.0/16", "147.145.0.0/16", "147.243.0.0/16", "148.7.0.0/16", "150.171.0.0/16", "150.242.48.0/22", "155.62.0.0/16", "157.31.0.0/16", "157.54.0.0/15", "157.56.0.0/14", "157.60.0.0/16", "158.23.0.0/16", "158.158.0.0/16", "159.27.0.0/16", "159.128.0.0/16", "163.228.0.0/16", "167.105.0.0/16", "167.220.0.0/16", "168.61.0.0/16", "168.62.0.0/15", "169.138.0.0/16", "170.165.0.0/16", "172.160.0.0/11", "172.200.0.0/13", "172.208.0.0/13", "191.232.0.0/13", "192.32.0.0/16", "192.48.225.0/24", "192.84.159.0/24", "192.84.160.0/23", "192.197.157.0/24", "192.237.67.0/24", "193.149.64.0/19", "193.221.113.0/24", "194.69.96.0/19", "194.110.197.0/24", "195.134.224.0/19", "198.105.232.0/22", "198.137.97.0/24", "198.180.95.0/24", "198.180.96.0/23", "198.200.130.0/24", "198.206.164.0/24", "199.30.16.0/20", "199.60.28.0/24", "199.74.210.0/24", "199.103.90.0/23", "199.103.122.0/24", "199.242.32.0/20", "199.242.48.0/21", "202.89.224.0/20", "204.13.120.0/21", "204.14.180.0/22", "204.79.135.0/24", "204.79.179.0/24", "204.79.181.0/24", "204.79.188.0/24", "204.79.195.0/24", "204.79.196.0/23", "204.79.252.0/24", "204.152.18.0/23", "204.152.140.0/23", "204.231.192.0/24", "204.231.194.0/23", "204.231.197.0/24", "204.231.198.0/23", "204.231.200.0/21", "204.231.208.0/20", "204.231.236.0/24", "205.174.224.0/20", "206.138.168.0/21", "206.191.224.0/19", "207.46.0.0/16", "207.68.128.0/18", "208.68.136.0/21", "208.76.44.0/22", "208.84.0.0/21", "209.240.192.0/19", "213.199.128.0/18", "216.32.180.0/22", "216.220.208.0/20")
    $linuxUpdateServerHostname = "LINUX-UPDATES-SHM-$($shm.id)".ToUpper()
    $shm.monitoring = [ordered]@{
        rg                = "$($shm.rgPrefix)_MONITORING".ToUpper()
        automationAccount = [ordered]@{
            name = "shm-$($shm.id)-automation".ToLower()
        }
        loggingWorkspace  = [ordered]@{
            name = "shm-$($shm.id)-loganalytics".ToLower()
        }
        privatelink       = [ordered]@{
            name = "shm-$($shm.id)-privatelinkscope".ToLower()
        }
        updateServers     = [ordered]@{
            externalIpAddresses = [ordered]@{
                azureAutomation = @(
                    "13.66.145.80", "13.69.109.177", "13.71.175.151", "13.71.199.178", "13.75.34.150", "13.77.55.200", "20.140.131.132", "20.192.168.149", "20.36.108.243", "20.49.90.25", "40.78.236.132", "40.78.236.133", "40.79.173.18", "40.79.187.166", "40.80.176.49", "51.105.77.83", "51.107.60.86", "52.138.229.87", "52.167.107.72", "52.167.107.74", "52.236.186.244"
                ) # *-jobruntimedata-prod-su1.azure-automation.net
                linux           = (
                    @("72.32.157.246", "87.238.57.227", "147.75.85.69", "217.196.149.55") + # apt.postgresql.org
                    @("91.189.91.38", "91.189.91.39", "185.125.190.36", "185.125.190.39") + # archive.ubuntu.com, changelogs.ubuntu.com, security.ubuntu.com
                    @("104.16.219.84", "104.16.218.84") + # database.clamav.net
                    @("104.131.190.124") + # dbeaver.io
                    @("152.199.20.126") + # developer.download.nvidia.com
                    @("104.18.26.123", "104.18.27.123") + # packages.gitlab.com
                    @("52.52.144.96", "54.176.201.225") + # packagecloud.io
                    @("104.21.71.41", "144.76.174.102", "172.67.143.23") + # qgis.org
                    $microsoftIpAddresses # packages.microsoft.com, azure.archive.ubuntu.com
                )
                windows         = @($microsoftIpAddresses) # for several Microsoft-owned endpoints
            }
            linux               = [ordered]@{
                adminPasswordSecretName = "shm-$($shm.id)-vm-admin-password-linux-update-server".ToLower()
                disks                   = [ordered]@{
                    os = [ordered]@{
                        sizeGb = "32"
                        type   = $shm.diskTypeDefault
                    }
                }
                hostname                = $linuxUpdateServerHostname
                ip                      = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.vnet.subnets.updateServers.cidr -Offset 4
                vmName                  = $linuxUpdateServerHostname
                vmSize                  = "Standard_B2ms"
            }
        }
    }

    # Firewall config
    # ---------------
    $shm.firewall = [ordered]@{
        name           = "FIREWALL-SHM-$($shm.id)".ToUpper()
        routeTableName = "ROUTE-TABLE-SHM-$($shm.id)".ToUpper()
    }

    # Secrets config
    # --------------
    $shm.keyVault = [ordered]@{
        rg          = "$($shm.rgPrefix)_SECRETS".ToUpper()
        name        = "kv-shm-$($shm.id)".ToLower() | Limit-StringLength -MaximumLength 24
        secretNames = [ordered]@{
            aadEmergencyAdminUsername = "shm-$($shm.id)-aad-emergency-admin-username".ToLower()
            aadEmergencyAdminPassword = "shm-$($shm.id)-aad-emergency-admin-password".ToLower()
            buildImageAdminUsername   = "shm-$($shm.id)-buildimage-admin-username".ToLower()
            buildImageAdminPassword   = "shm-$($shm.id)-buildimage-admin-password".ToLower()
            domainAdminUsername       = "shm-$($shm.id)-domain-admin-username".ToLower()
            domainAdminPassword       = "shm-$($shm.id)-domain-admin-password".ToLower()
            vmAdminUsername           = "shm-$($shm.id)-vm-admin-username".ToLower()
            vpnCaCertificate          = "shm-$($shm.id)-vpn-ca-cert".ToLower()
            vpnCaCertificatePlain     = "shm-$($shm.id)-vpn-ca-cert-plain".ToLower()
            vpnCaCertPassword         = "shm-$($shm.id)-vpn-ca-cert-password".ToLower()
            vpnClientCertificate      = "shm-$($shm.id)-vpn-client-cert".ToLower()
            vpnClientCertPassword     = "shm-$($shm.id)-vpn-client-cert-password".ToLower()
        }
    }

    # SHM users
    # ---------
    $shm.users = [ordered]@{
        computerManagers = [ordered]@{
            databaseServers   = [ordered]@{
                name               = "$($shm.domain.netbiosName) Database Servers Manager"
                samAccountName     = "$($shm.id)databasesrvrs".ToLower() | Limit-StringLength -MaximumLength 20
                passwordSecretName = "shm-$($shm.id)-computer-manager-password-database-servers".ToLower()
            }
            identityServers   = [ordered]@{
                name               = "$($shm.domain.netbiosName) Identity Servers Manager"
                samAccountName     = "$($shm.id)identitysrvrs".ToLower() | Limit-StringLength -MaximumLength 20
                passwordSecretName = "shm-$($shm.id)-computer-manager-password-identity-servers".ToLower()
            }
            linuxServers      = [ordered]@{
                name               = "$($shm.domain.netbiosName) Linux Servers Manager"
                samAccountName     = "$($shm.id)linuxsrvrs".ToLower() | Limit-StringLength -MaximumLength 20
                passwordSecretName = "shm-$($shm.id)-computer-manager-password-linux-servers".ToLower()
            }
            rdsGatewayServers = [ordered]@{
                name               = "$($shm.domain.netbiosName) RDS Gateway Manager"
                samAccountName     = "$($shm.id)gatewaysrvrs".ToLower() | Limit-StringLength -MaximumLength 20
                passwordSecretName = "shm-$($shm.id)-computer-manager-password-rds-gateway-servers".ToLower()
            }
            rdsSessionServers = [ordered]@{
                name               = "$($shm.domain.netbiosName) RDS Session Servers Manager"
                samAccountName     = "$($shm.id)sessionsrvrs".ToLower() | Limit-StringLength -MaximumLength 20
                passwordSecretName = "shm-$($shm.id)-computer-manager-password-rds-session-servers".ToLower()
            }
        }
        serviceAccounts  = [ordered]@{
            aadLocalSync = [ordered]@{
                name               = "$($shm.domain.netbiosName) Local AD Sync Administrator"
                samAccountName     = "$($shm.id)localadsync".ToLower() | Limit-StringLength -MaximumLength 20
                passwordSecretName = "shm-$($shm.id)-aad-localsync-password".ToLower()
                usernameSecretName = "shm-$($shm.id)-aad-localsync-username".ToLower()
            }
        }
    }

    # Domain controller config
    # ------------------------
    $hostname = "DC1-SHM-$($shm.id)".ToUpper() | Limit-StringLength -MaximumLength 15
    $shm.dc = [ordered]@{
        rg                         = "$($shm.rgPrefix)_DC".ToUpper()
        vmName                     = $hostname
        vmSize                     = "Standard_D2s_v3"
        hostname                   = $hostname
        hostnameLower              = $hostname.ToLower()
        hostnameUpper              = $hostname.ToUpper()
        fqdn                       = "${hostname}.$($shm.domain.fqdn)"
        ip                         = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.vnet.subnets.identity.cidr -Offset 4
        external_dns_resolver      = "168.63.129.16"  # https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
        installationDirectory      = "C:\Installation"
        adDirectory                = "C:\ActiveDirectory"
        safemodePasswordSecretName = "shm-$($shm.id)-vm-safemode-password-dc".ToLower()
        disks                      = [ordered]@{
            os = [ordered]@{
                sizeGb = "128"
                type   = $shm.diskTypeDefault
            }
        }
    }

    # Backup domain controller config
    # -------------------------------
    $hostname = "DC2-SHM-$($shm.id)".ToUpper() | Limit-StringLength -MaximumLength 15
    $shm.dcb = [ordered]@{
        vmName   = $hostname
        hostname = $hostname
        fqdn     = "${hostname}.$($shm.domain.fqdn)"
        ip       = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.vnet.subnets.identity.cidr -Offset 5
    }

    # NPS config
    # ----------
    $hostname = "NPS-SHM-$($shm.id)".ToUpper() | Limit-StringLength -MaximumLength 15
    $shm.nps = [ordered]@{
        adminPasswordSecretName = "shm-$($shm.id)-vm-admin-password-nps".ToLower()
        rg                      = "$($shm.rgPrefix)_NPS".ToUpper()
        vmName                  = $hostname
        vmSize                  = "Standard_D2s_v3"
        hostname                = $hostname
        ip                      = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.vnet.subnets.identity.cidr -Offset 6
        installationDirectory   = "C:\Installation"
        disks                   = [ordered]@{
            os = [ordered]@{
                sizeGb = "128"
                type   = $shm.diskTypeDefault
            }
        }
    }

    # Storage config
    # --------------
    $shmStoragePrefix = "shm$($shm.id)"
    $shmStorageSuffix = New-RandomLetters -SeedPhrase "$($shm.subscriptionName)$($shm.id)"
    $storageRg = "$($shm.rgPrefix)_STORAGE".ToUpper()
    $shm.storage = [ordered]@{
        artifacts       = [ordered]@{
            rg          = $storageRg
            accountName = "${shmStoragePrefix}artifacts${shmStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
            containers  = [ordered]@{
                shmArtifactsDC  = "shm-artifacts-dc"
                shmArtifactsNPS = "shm-artifacts-nps"
                shmDesiredState = "shm-desired-state"
            }
        }
        bootdiagnostics = [ordered]@{
            rg          = $storageRg
            accountName = "${shmStoragePrefix}bootdiags${shmStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
        }
        persistentdata  = [ordered]@{
            rg = "$($shm.rgPrefix)_PERSISTENT_DATA".ToUpper()
        }
    }

    # DNS config
    # ----------
    $shm.dns = [ordered]@{
        subscriptionName = $shmConfigBase.dnsRecords.subscriptionName ? $shmConfigBase.dnsRecords.subscriptionName : $shm.subscriptionName
        rg               = $shmConfigBase.dnsRecords.resourceGroupName ? $shmConfigBase.dnsRecords.resourceGroupName : "$($shm.rgPrefix)_DNS_RECORDS".ToUpper()
    }

    # Package repository configuration
    # --------------------------------
    $shm.repositories = [ordered]@{
        rg = "$($shm.rgPrefix)_PACKAGE_REPOSITORIES".ToUpper()
    }
    foreach ($tier in @(2, 3)) {
        $shm.repositories["tier${tier}"] = [ordered]@{}
        # Tier 2 defaults to using a proxy unless otherwise specified
        if ($tier -eq 2) {
            $LocalRepositoryTypes = ($shmConfigBase.repositoryType.tier2 -and ($shmConfigBase.repositoryType.tier2.ToLower() -eq "mirror")) ? @("mirrorsExternal", "mirrorsInternal") : @("proxies")
        }
        # Tier 3 defaults to using a proxy unless otherwise specified
        if ($tier -eq 3) {
            $LocalRepositoryTypes = ($shmConfigBase.repositoryType.tier3 -and ($shmConfigBase.repositoryType.tier3.ToLower() -eq "mirror")) ? @("mirrorsExternal", "mirrorsInternal") : @("proxies")
        }
        # Tier 4 requires the use of mirrors
        if ($tier -eq 4) {
            $LocalRepositoryTypes = @("mirrorsExternal", "mirrorsInternal")
        }
        foreach ($LocalRepositoryType in $LocalRepositoryTypes) {
            $shm.repositories["tier${tier}"][$LocalRepositoryType] = [ordered]@{}
            $RemoteRepositories = ($LocalRepositoryType -eq "proxies") ? "many" : @("cran", "pypi")
            $LocalRepositoryShort = $LocalRepositoryType.Replace("proxies", "proxy").Replace("mirrors", "mirror-")
            foreach ($RemoteRepository in $RemoteRepositories) {
                if ($RemoteRepository -eq "cran") {
                    $dataDiskSizeGb = ($tier -eq 2) ? 128 : 32
                    $ipOffset = 4
                } elseif ($RemoteRepository -eq "pypi") {
                    $dataDiskSizeGb = ($tier -eq 2) ? 8192 : 1024
                    $ipOffset = 5
                } else {
                    $dataDiskSizeGb = $null
                    $ipOffset = 6
                }
                $vmName = "SHM-$($shm.id)-${RemoteRepository}-REPOSITORY-${LocalRepositoryShort}-TIER-${tier}".ToUpper()
                $shm.repositories["tier${tier}"][$LocalRepositoryType][$RemoteRepository] = [ordered]@{
                    adminPasswordSecretName = "shm-$($shm.id)-vm-admin-password-${RemoteRepository}-repository-${LocalRepositoryShort}-tier-${tier}".ToLower()
                    disks                   = [ordered]@{
                        os = [ordered]@{
                            sizeGb = 32
                            type   = $shm.diskTypeDefault
                        }
                    }
                    ipAddress               = Get-NextAvailableIpInRange -IpRangeCidr $shm.network["vnetRepositoriesTier${tier}"].subnets[$LocalRepositoryType].cidr -Offset $ipOffset
                    vmName                  = $vmName
                    vmSize                  = "Standard_B2ms"
                }
                if ($dataDiskSizeGb) {
                    $shm.repositories["tier${tier}"][$LocalRepositoryType][$RemoteRepository].disks["data"] = [ordered]@{
                        sizeGb = $dataDiskSizeGb
                        type   = $shm.diskTypeDefault
                    }
                }
                if ($LocalRepositoryType -eq "proxies") {
                    $shm.repositories["tier${tier}"][$LocalRepositoryType][$RemoteRepository]["applicationAdminPasswordSecretName"] = "shm-$($shm.id)-application-admin-password-${RemoteRepository}-repository-${LocalRepositoryShort}-tier-${tier}".ToLower()
                }
            }
        }
    }

    # Apply overrides (if any exist)
    # ------------------------------
    if ($shmConfigBase.overrides) {
        Copy-HashtableOverrides -Source $shmConfigBase.overrides -Target $shm
    }

    return (ConvertTo-SortedHashtable -Sortable $shm)
}
Export-ModuleMember -Function Get-ShmConfig


# Get a list of resource groups belonging to a particular SRE
# -----------------------------------------------------------
function Get-ShmResourceGroups {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "SRE config")]
        [System.Collections.IDictionary]$shmConfig
    )
    $originalContext = Get-AzContext
    $excludedResourceGroups = Find-AllMatchingKeys -Hashtable $shmConfig.srdImage -Key "rg"
    $potentialResourceGroups = Find-AllMatchingKeys -Hashtable $shmConfig -Key "rg" | Where-Object { -not $excludedResourceGroups.Contains($_) }
    try {
        $null = Set-AzContext -SubscriptionId $shmConfig.subscriptionName -ErrorAction Stop
        $availableResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -in $potentialResourceGroups })
    } finally {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
    return $availableResourceGroups
}
Export-ModuleMember -Function Get-ShmResourceGroups


# Add a new SRE configuration
# ---------------------------
function Get-SreConfig {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
        [string]$shmId,
        [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
        [string]$sreId
    )
    # Import minimal management config parameters from JSON config file - we can derive the rest from these
    $sreConfigBase = Get-CoreConfig -shmId $shmId -sreId $sreId

    # Secure research environment config
    # ----------------------------------
    # Check that one of the allowed remote desktop providers is selected
    $remoteDesktopProviders = @("ApacheGuacamole", "MicrosoftRDS")
    if (-not $sreConfigBase.remoteDesktopProvider) {
        Add-LogMessage -Level Warning "No remoteDesktopType was provided. Defaulting to $($remoteDesktopProviders[0])"
        $sreConfigBase.remoteDesktopProvider = $remoteDesktopProviders[0]
    }
    if (-not $remoteDesktopProviders.Contains($sreConfigBase.remoteDesktopProvider)) {
        Add-LogMessage -Level Fatal "Did not recognise remote desktop provider '$($sreConfigBase.remoteDesktopProvider)' as one of the allowed remote desktop types: $remoteDesktopProviders"
    }
    if (
        ($sreConfigBase.remoteDesktopProvider -eq "MicrosoftRDS") -and (-not @(2, 3, 4).Contains([int]$sreConfigBase.tier))
    ) {
        Add-LogMessage -Level Fatal "RemoteDesktopProvider '$($sreConfigBase.remoteDesktopProvider)' cannot be used for tier '$($sreConfigBase.tier)'"
    }
    # Setup the basic config
    $config = [ordered]@{
        shm = Get-ShmConfig -shmId $sreConfigBase.shmId
        sre = [ordered]@{
            id                 = $sreConfigBase.sreId | Limit-StringLength -MaximumLength 7 -FailureIsFatal
            rgPrefix           = $sreConfigBase.overrides.sre.rgPrefix ? $sreConfigBase.overrides.sre.rgPrefix : "RG_SHM_$($sreConfigBase.shmId)_SRE_$($sreConfigBase.sreId)".ToUpper()
            nsgPrefix          = $sreConfigBase.overrides.sre.nsgPrefix ? $sreConfigBase.overrides.sre.nsgPrefix : "NSG_SHM_$($sreConfigBase.shmId)_SRE_$($sreConfigBase.sreId)".ToUpper()
            shortName          = "sre-$($sreConfigBase.sreId)".ToLower()
            subscriptionName   = $sreConfigBase.subscriptionName
            tier               = $sreConfigBase.tier
            remoteDesktop      = [ordered]@{
                provider = $sreConfigBase.remoteDesktopProvider
            }
            storageTypeDefault = "Standard_GRS"
            diskTypeDefault    = "Standard_LRS"
        }
    }
    $config.sre.azureAdminGroupName = $sreConfigBase.azureAdminGroupName ? $sreConfigBase.azureAdminGroupName : $config.shm.azureAdminGroupName
    $config.sre.location = $config.shm.location

    # Set the default timezone to match the SHM timezone
    $config.sre.time = [ordered]@{
        timezone = [ordered]@{
            linux   = $config.shm.time.timezone.linux
            windows = $config.shm.time.timezone.windows
        }
    }

    # Ensure that this tier is supported
    if (-not @("0", "1", "2", "3").Contains($config.sre.tier)) {
        Add-LogMessage -Level Fatal "Tier '$($config.sre.tier)' not supported (NOTE: Tier must be provided as a string in the core SRE config.)"
    }

    # Domain config
    # -------------
    $sreDomain = $sreConfigBase.domain ? $sreConfigBase.domain : "$($config.sre.id).$($config.shm.domain.fqdn)".ToLower()
    $config.sre.domain = [ordered]@{
        dn          = "DC=$($sreDomain.Replace('.',',DC='))"
        fqdn        = $sreDomain
        netbiosName = $($config.sre.id).ToUpper() | Limit-StringLength -MaximumLength 15 -FailureIsFatal
    }
    $config.sre.domain.securityGroups = [ordered]@{
        dataAdministrators   = [ordered]@{ name = "SG $($config.sre.domain.netbiosName) Data Administrators" }
        systemAdministrators = [ordered]@{ name = "SG $($config.sre.domain.netbiosName) System Administrators" }
        researchUsers        = [ordered]@{ name = "SG $($config.sre.domain.netbiosName) Research Users" }
    }
    foreach ($groupName in $config.sre.domain.securityGroups.Keys) {
        $config.sre.domain.securityGroups[$groupName].description = $config.sre.domain.securityGroups[$groupName].name
    }

    # Network config
    # --------------
    # Deconstruct base address prefix to allow easy construction of IP based parameters
    $srePrefixOctets = $sreConfigBase.ipPrefix.Split('.')
    $sreBasePrefix = "$($srePrefixOctets[0]).$($srePrefixOctets[1])"
    $sreThirdOctet = $srePrefixOctets[2]
    $config.sre.network = [ordered]@{
        vnet = [ordered]@{
            rg      = "$($config.sre.rgPrefix)_NETWORKING".ToUpper()
            name    = "VNET_SHM_$($config.shm.id)_SRE_$($config.sre.id)".ToUpper()
            cidr    = "${sreBasePrefix}.${sreThirdOctet}.0/21"
            subnets = [ordered]@{
                deployment    = [ordered]@{
                    name = "DeploymentSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet).0/24"
                    nsg  = [ordered]@{
                        name  = "$($config.sre.nsgPrefix)_DEPLOYMENT".ToUpper()
                        rules = "sre-nsg-rules-deployment.json"
                    }
                }
                remoteDesktop = [ordered]@{ # note that further details are added below
                    name = "RemoteDesktopSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 1).0/24"
                }
                data          = [ordered]@{
                    name = "PrivateDataSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 2).0/24"
                }
                databases     = [ordered]@{
                    name = "DatabasesSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 3).0/24"
                    nsg  = [ordered]@{
                        name  = "$($config.sre.nsgPrefix)_DATABASES".ToUpper()
                        rules = "sre-nsg-rules-databases.json"
                    }
                }
                compute       = [ordered]@{
                    name = "ComputeSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 4).0/24"
                    nsg  = [ordered]@{
                        name  = "$($config.sre.nsgPrefix)_COMPUTE".ToUpper()
                        rules = "sre-nsg-rules-compute.json"
                    }
                }
                webapps       = [ordered]@{
                    name = "WebappsSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 5).0/24"
                    nsg  = [ordered]@{
                        name  = "$($config.sre.nsgPrefix)_WEBAPPS".ToUpper()
                        rules = "sre-nsg-rules-webapps.json"
                    }
                }
            }
        }
    }


    # Firewall config
    # ---------------
    $config.sre.firewall = [ordered]@{
        routeTableName = "ROUTE-TABLE-SRE-$($config.sre.id)".ToUpper()
    }

    # Storage config
    # --------------
    $storageRg = "$($config.sre.rgPrefix)_STORAGE".ToUpper()
    $sreStoragePrefix = "$($config.shm.id)$($config.sre.id)"
    $sreStorageSuffix = New-RandomLetters -SeedPhrase "$($config.sre.subscriptionName)$($config.sre.id)"
    $config.sre.storage = [ordered]@{
        accessPolicies  = [ordered]@{
            readOnly  = [ordered]@{
                permissions = "rl"
            }
            readWrite = [ordered]@{
                permissions = "racwdl"
            }
        }
        artifacts       = [ordered]@{
            account    = [ordered]@{
                name               = "${sreStoragePrefix}artifacts${sreStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
                storageKind        = "BlobStorage"
                performance        = $config.sre.storageTypeDefault # see https://docs.microsoft.com/en-us/azure/storage/common/storage-account-overview#types-of-storage-accounts for allowed types
                accessTier         = "Cool"
                allowedIpAddresses = $sreConfigBase.deploymentIpAddresses ? @($sreConfigBase.deploymentIpAddresses) : "any"
            }
            containers = [ordered]@{
                sreArtifactsRDS = "sre-artifacts-rds"
                sreScriptsRDS   = "sre-scripts-rds"
            }
            rg         = $storageRg
        }
        bootdiagnostics = [ordered]@{
            accountName = "${sreStoragePrefix}bootdiags${sreStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
            rg          = $storageRg
        }
        userdata        = [ordered]@{
            account    = [ordered]@{
                name        = "${sreStoragePrefix}userdata${sreStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
                storageKind = "FileStorage"
                performance = $config.sre.storageTypeDefault.Contains("LRS") ? "Premium_LRS" : "Premium_ZRS" # see https://docs.microsoft.com/en-us/azure/storage/common/storage-account-overview#types-of-storage-accounts for allowed types
                accessTier  = "Hot"
                rg          = $storageRg
            }
            containers = [ordered]@{
                shared = [ordered]@{
                    accessPolicyName = "readWrite"
                    mountType        = "NFS"
                    sizeGb           = "1024"
                }
                home   = [ordered]@{
                    accessPolicyName = "readWrite"
                    mountType        = "NFS"
                    sizeGb           = "1024"
                }
            }
        }
        persistentdata  = [ordered]@{
            account    = [ordered]@{
                name               = "${sreStoragePrefix}data${srestorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
                storageKind        = "StorageV2"
                performance        = $config.sre.storageTypeDefault # see https://docs.microsoft.com/en-us/azure/storage/common/storage-account-overview#types-of-storage-accounts for allowed types
                accessTier         = "Hot"
                allowedIpAddresses = $sreConfigBase.dataAdminIpAddresses ? @($sreConfigBase.dataAdminIpAddresses) : $shm.srdImage.build.nsg.allowedIpAddresses
            }
            containers = [ordered]@{
                backup  = [ordered]@{
                    accessPolicyName = "readWrite"
                    mountType        = "BlobSMB"
                }
                ingress = [ordered]@{
                    accessPolicyName = "readOnly"
                    mountType        = "BlobSMB"
                }
                egress  = [ordered]@{
                    accessPolicyName = "readWrite"
                    mountType        = "BlobSMB"
                }
            }
        }
    }
    foreach ($containerName in $config.sre.storage.persistentdata.containers.Keys) {
        $config.sre.storage.persistentdata.containers[$containerName].connectionSecretName = "sre-$($config.sre.id)-data-${containerName}-connection-$($config.sre.storage.persistentdata.containers[$containerName].accessPolicyName)".ToLower()
    }


    # Backup config
    # -------------
    $config.sre.backup = [ordered]@{
        rg    = "$($config.sre.rgPrefix)_BACKUP".ToUpper()
        vault = [ordered]@{
            name = "bv-$($config.shm.id)-sre-$($config.sre.id)"
        }
        blob  = [ordered]@{
            policy_name = "blobbackuppolicy"
        }
        disk  = [ordered]@{
            policy_name = "diskbackuppolicy"
        }
    }

    # Secrets config
    # --------------
    $config.sre.keyVault = [ordered]@{
        name        = "kv-$($config.shm.id)-sre-$($config.sre.id)".ToLower() | Limit-StringLength -MaximumLength 24
        rg          = "$($config.sre.rgPrefix)_SECRETS".ToUpper()
        secretNames = [ordered]@{
            adminUsername          = "$($config.sre.shortName)-vm-admin-username"
            letsEncryptCertificate = "$($config.sre.shortName)-lets-encrypt-certificate"
            npsSecret              = "$($config.sre.shortName)-other-nps-secret"
        }
    }

    # SRE users
    # ---------
    $config.sre.users = [ordered]@{
        serviceAccounts = [ordered]@{
            ldapSearch = [ordered]@{
                name               = "$($config.sre.domain.netbiosName) LDAP Search Service Account"
                samAccountName     = "$($config.sre.id)ldapsearch".ToLower() | Limit-StringLength -MaximumLength 20
                passwordSecretName = "$($config.sre.shortName)-other-service-account-password-ldap-search"
            }
            postgres   = [ordered]@{
                name               = "$($config.sre.domain.netbiosName) Postgres DB Service Account"
                samAccountName     = "$($config.sre.id)dbpostgres".ToLower() | Limit-StringLength -MaximumLength 20
                passwordSecretName = "$($config.sre.shortName)-db-service-account-password-postgres"
            }
        }
    }

    # Remote desktop either through Apache Guacamole or Microsoft RDS
    # ---------------------------------------------------------------
    $config.sre.remoteDesktop.rg = "$($config.sre.rgPrefix)_REMOTE_DESKTOP".ToUpper()
    if ($config.sre.remoteDesktop.provider -eq "ApacheGuacamole") {
        $config.sre.network.vnet.subnets.remoteDesktop.nsg = [ordered]@{
            name  = "$($config.sre.nsgPrefix)_GUACAMOLE".ToUpper()
            rules = "sre-nsg-rules-guacamole.json"
        }
        $config.sre.remoteDesktop.guacamole = [ordered]@{
            adminPasswordSecretName         = "$($config.sre.shortName)-vm-admin-password-guacamole"
            databaseAdminPasswordSecretName = "$($config.sre.shortName)-db-admin-password-guacamole"
            vmName                          = "GUACAMOLE-SRE-$($config.sre.id)".ToUpper()
            vmSize                          = "Standard_DS2_v2"
            ip                              = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.remoteDesktop.cidr -Offset 4
            disks                           = [ordered]@{
                os = [ordered]@{
                    sizeGb = "128"
                    type   = $config.sre.diskTypeDefault
                }
            }
        }
    } elseif ($config.sre.remoteDesktop.provider -eq "MicrosoftRDS") {
        $config.sre.remoteDesktop.gateway = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-rds-gateway"
            vmName                  = "RDG-SRE-$($config.sre.id)".ToUpper() | Limit-StringLength -MaximumLength 15
            vmSize                  = "Standard_DS2_v2"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.remoteDesktop.cidr -Offset 4
            installationDirectory   = "C:\Installation"
            nsg                     = [ordered]@{
                name  = "$($config.sre.nsgPrefix)_RDS_SERVER".ToUpper()
                rules = "sre-nsg-rules-gateway.json"
            }
            disks                   = [ordered]@{
                data = [ordered]@{
                    sizeGb = "1023"
                    type   = $config.sre.diskTypeDefault
                }
                os   = [ordered]@{
                    sizeGb = "128"
                    type   = $config.sre.diskTypeDefault
                }
            }
        }
        $config.sre.remoteDesktop.appSessionHost = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-rds-sh1"
            vmName                  = "APP-SRE-$($config.sre.id)".ToUpper() | Limit-StringLength -MaximumLength 15
            vmSize                  = "Standard_DS2_v2"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.remoteDesktop.cidr -Offset 5
            nsg                     = [ordered]@{
                name  = "$($config.sre.nsgPrefix)_RDS_SESSION_HOSTS".ToUpper()
                rules = "sre-nsg-rules-session-hosts.json"
            }
            disks                   = [ordered]@{
                os = [ordered]@{
                    sizeGb = "128"
                    type   = $config.sre.diskTypeDefault
                }
            }
        }
    } else {
        Add-LogMessage -Level Fatal "Remote desktop type '$($config.sre.remoteDesktop.type)' was not recognised!"
    }
    # Construct the hostname and FQDN for each VM
    foreach ($server in $config.sre.remoteDesktop.Keys) {
        if (-not $config.sre.remoteDesktop[$server].vmName) { continue }
        $config.sre.remoteDesktop[$server].hostname = $config.sre.remoteDesktop[$server].vmName
        $config.sre.remoteDesktop[$server].fqdn = "$($config.sre.remoteDesktop[$server].vmName).$($config.shm.domain.fqdn)"
    }

    # Set the appropriate tier-dependent network rules for the remote desktop server
    # ------------------------------------------------------------------------------
    $config.sre.remoteDesktop.networkRules = [ordered]@{}
    # Inbound: which IPs can access the Safe Haven (if 'default' is given then apply sensible defaults)
    if ($sreConfigBase.inboundAccessFrom -eq "default") {
        if (@("0", "1").Contains($config.sre.tier)) {
            $config.sre.remoteDesktop.networkRules.allowedSources = "Internet"
        } elseif ($config.sre.tier -eq "2") {
            $config.sre.remoteDesktop.networkRules.allowedSources = "193.60.220.253"
        } elseif (@("3", "4").Contains($config.sre.tier)) {
            $config.sre.remoteDesktop.networkRules.allowedSources = "193.60.220.240"
        }
    } elseif ($sreConfigBase.inboundAccessFrom -eq "anywhere") {
        $config.sre.remoteDesktop.networkRules.allowedSources = "Internet"
    } else {
        $config.sre.remoteDesktop.networkRules.allowedSources = @($sreConfigBase.inboundAccessFrom)
    }
    # Outbound: whether internet access is allowed (if 'default' is given then apply sensible defaults)
    if ($sreConfigBase.outboundInternetAccess -eq "default") {
        if (@("0", "1").Contains($config.sre.tier)) {
            $config.sre.remoteDesktop.networkRules.outboundInternet = "Allow"
        } elseif (@("2", "3", "4").Contains($config.sre.tier)) {
            $config.sre.remoteDesktop.networkRules.outboundInternet = "Deny"
        }
    } elseif (@("yes", "allow", "permit").Contains($($sreConfigBase.outboundInternetAccess).ToLower())) {
        $config.sre.remoteDesktop.networkRules.outboundInternet = "Allow"
    } elseif (@("no", "deny", "forbid").Contains($($sreConfigBase.outboundInternetAccess).ToLower())) {
        $config.sre.remoteDesktop.networkRules.outboundInternet = "Deny"
    } else {
        $config.sre.remoteDesktop.networkRules.outboundInternet = @($sreConfigBase.outboundInternet)
    }
    # Copy-and-paste
    if (@("0", "1").Contains($config.sre.tier)) {
        $config.sre.remoteDesktop.networkRules.copyAllowed = $true
        $config.sre.remoteDesktop.networkRules.pasteAllowed = $true
    } elseif (@("2", "3", "4").Contains($config.sre.tier)) {
        $config.sre.remoteDesktop.networkRules.copyAllowed = $false
        $config.sre.remoteDesktop.networkRules.pasteAllowed = $false
    }
    # Since we cannot 'Allow' the AzurePlatformDNS endpoint we set this flag which can be used to turn-off the section in the mustache template
    $config.sre.remoteDesktop.networkRules.includeAzurePlatformDnsRule = ($config.sre.remoteDesktop.networkRules.outboundInternet -ne "Allow")


    # CoCalc, CodiMD and Gitlab servers
    # ---------------------------------
    $config.sre.webapps = [ordered]@{
        rg     = "$($config.sre.rgPrefix)_WEBAPPS".ToUpper()
        cocalc = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-cocalc"
            dockerVersion           = "latest"
            hostname                = "COCALC"
            vmSize                  = "Standard_D2s_v3"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.webapps.cidr -Offset 7
            osVersion               = "Ubuntu-latest"
            disks                   = [ordered]@{
                data = [ordered]@{
                    sizeGb = "512"
                    type   = $config.sre.diskTypeDefault
                }
                os   = [ordered]@{
                    sizeGb = "32"
                    type   = $config.sre.diskTypeDefault
                }
            }
        }
        codimd = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-codimd"
            hostname                = "CODIMD"
            vmSize                  = "Standard_D2s_v3"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.webapps.cidr -Offset 6
            osVersion               = "Ubuntu-latest"
            codimd                  = [ordered]@{
                dockerVersion = "2.4.1-cjk"
            }
            postgres                = [ordered]@{
                passwordSecretName = "$($config.sre.shortName)-other-codimd-password-postgresdb"
                dockerVersion      = "13.4-alpine"
            }
            disks                   = [ordered]@{
                data = [ordered]@{
                    sizeGb = "512"
                    type   = $config.sre.diskTypeDefault
                }
                os   = [ordered]@{
                    sizeGb = "32"
                    type   = $config.sre.diskTypeDefault
                }
            }
        }
        gitlab = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-gitlab"
            hostname                = "GITLAB"
            vmSize                  = "Standard_D2s_v3"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.webapps.cidr -Offset 5
            rootPasswordSecretName  = "$($config.sre.shortName)-other-gitlab-root-password"
            osVersion               = "Ubuntu-latest"
            disks                   = [ordered]@{
                data = [ordered]@{
                    sizeGb = "512"
                    type   = $config.sre.diskTypeDefault
                }
                os   = [ordered]@{
                    sizeGb = "32"
                    type   = $config.sre.diskTypeDefault
                }
            }
        }
    }
    # Construct the hostname and FQDN for each VM
    foreach ($server in $config.sre.webapps.Keys) {
        if ($config.sre.webapps[$server] -IsNot [System.Collections.Specialized.OrderedDictionary]) { continue }
        $config.sre.webapps[$server].fqdn = "$($config.sre.webapps[$server].hostname).$($config.sre.domain.fqdn)"
        $config.sre.webapps[$server].vmName = "$($config.sre.webapps[$server].hostname)-SRE-$($config.sre.id)".ToUpper()
    }


    # Databases
    # ---------
    $config.sre.databases = [ordered]@{
        rg = "$($config.sre.rgPrefix)_DATABASES".ToUpper()
    }
    $dbConfig = @{
        MSSQL      = @{port = "1433"; prefix = "MSSQL"; sku = "sqldev-gen2" }
        PostgreSQL = @{port = "5432"; prefix = "PSTGRS"; sku = "Ubuntu-latest" }
    }
    $ipOffset = 4
    foreach ($databaseType in $sreConfigBase.databases) {
        if (-not @($dbConfig.Keys).Contains($databaseType)) {
            Add-LogMessage -Level Fatal "Database type '$databaseType' was not recognised!"
        }
        $config.sre.databases["db$($databaseType.ToLower())"] = [ordered]@{
            adminPasswordSecretName   = "$($config.sre.shortName)-vm-admin-password-$($databaseType.ToLower())"
            dbAdminUsernameSecretName = "$($config.sre.shortName)-db-admin-username-$($databaseType.ToLower())"
            dbAdminPasswordSecretName = "$($config.sre.shortName)-db-admin-password-$($databaseType.ToLower())"
            vmName                    = "$($dbConfig[$databaseType].prefix)-$($config.sre.id)".ToUpper() | Limit-StringLength -MaximumLength 15
            type                      = $databaseType
            ip                        = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.databases.cidr -Offset $ipOffset
            port                      = $dbConfig[$databaseType].port
            sku                       = $dbConfig[$databaseType].sku
            subnet                    = "databases"
            vmSize                    = "Standard_DS2_v2"
            disks                     = [ordered]@{
                data = [ordered]@{
                    sizeGb = "1024"
                    type   = $config.sre.diskTypeDefault
                }
                os   = [ordered]@{
                    sizeGb = "128"
                    type   = $config.sre.diskTypeDefault
                }
            }
        }
        if ($databaseType -eq "MSSQL") { $config.sre.databases["db$($databaseType.ToLower())"]["enableSSIS"] = $true }
        $ipOffset += 1
    }

    # Secure Research Desktop VMs
    # ---------------------------
    $config.sre.srd = [ordered]@{
        adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-compute"
        rg                      = "$($config.sre.rgPrefix)_COMPUTE".ToUpper()
        vmImage                 = [ordered]@{
            type    = $sreConfigBase.computeVmImage.type
            version = $sreConfigBase.computeVmImage.version
        }
        vmSizeDefault           = "Standard_D2s_v3"
        disks                   = [ordered]@{
            os      = [ordered]@{
                sizeGb = "default"
                type   = "StandardSSD_LRS" # explicitly override defaults and use SSD for SRD disks
            }
            scratch = [ordered]@{
                sizeGb = "1024"
                type   = "StandardSSD_LRS" # explicitly override defaults and use SSD for SRD disks
            }
        }
    }

    # Package repositories
    # --------------------
    if (@(0, 1).Contains([int]$config.sre.tier)) {
        # For tiers 0 and 1 use pypi.org and cran.r-project.org directly.
        $pypiUrl = "https://pypi.org"
        $cranUrl = "https://cran.r-project.org"
        $repositoryVNetName = $null
        $repositoryVNetCidr = $null
    } else {
        # If using the Nexus proxy then the two repositories are hosted on the same VM
        $repositoryConfig = $config.shm.repositories["tier$($config.sre.tier)"]
        if ($repositoryConfig.proxies) {
            $cranUrl = "http://$($repositoryConfig.proxies.many.ipAddress):80/repository/cran-proxy"
            $pypiUrl = "http://$($repositoryConfig.proxies.many.ipAddress):80/repository/pypi-proxy"
            $repositoryVNetName = $config.shm.network["vnetRepositoriesTier$($config.sre.tier)"].name
            $repositoryVNetCidr = $config.shm.network["vnetRepositoriesTier$($config.sre.tier)"].cidr
        # Repository mirrors use port 3128 (PyPI) or port 80 (CRAN)
        } elseif ($repositoryConfig.mirrorsInternal) {
            $cranUrl = "http://$($repositoryConfig.mirrorsInternal.cran.ipAddress)"
            $pypiUrl = "http://$($repositoryConfig.mirrorsInternal.pypi.ipAddress):3128"
            $repositoryVNetName = $config.shm.network["vnetRepositoriesTier$($config.sre.tier)"].name
            $repositoryVNetCidr = $config.shm.network["vnetRepositoriesTier$($config.sre.tier)"].cidr
        } else {
            Add-LogMessage -Level Fatal "Unknown repository source for tier $($config.sre.tier) SRE!"
        }
    }
    # We want to extract the hostname from PyPI URLs in any of the following forms
    # 1. http://10.10.2.20:3128                      => 10.10.2.20
    # 2. https://pypi.org                            => pypi.org
    # 3. http://10.10.3.10:80/repository/pypi-proxy  => 10.10.3.10
    $pypiHost = ($pypiUrl -match "https*:\/\/([^:]*)([:0-9]*).*") ? $Matches[1] : ""
    $pypiIndex = $config.sre.nexus ? "${pypiUrl}/pypi" : $pypiUrl
    $config.sre.repositories = [ordered]@{
        cran    = [ordered]@{
            url = $cranUrl
        }
        pypi    = [ordered]@{
            host     = $pypiHost
            index    = $pypiIndex
            indexUrl = "${pypiUrl}/simple"
        }
        network = [ordered]@{
            name = $repositoryVNetName
            cidr = $repositoryVNetCidr
        }
    }

    # Apply overrides (if any exist)
    # ------------------------------
    if ($sreConfigBase.overrides) {
        Copy-HashtableOverrides -Source $sreConfigBase.overrides -Target $config
    }

    return (ConvertTo-SortedHashtable -Sortable $config)
}
Export-ModuleMember -Function Get-SreConfig


# Get a list of resource groups belonging to a particular SRE
# -----------------------------------------------------------
function Get-SreResourceGroups {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "SRE config")]
        [System.Collections.IDictionary]$sreConfig
    )
    $originalContext = Get-AzContext
    $potentialResourceGroups = Find-AllMatchingKeys -Hashtable $sreConfig.sre -Key "rg"
    try {
        $null = Set-AzContext -SubscriptionId $sreConfig.sre.subscriptionName -ErrorAction Stop
        $availableResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -in $potentialResourceGroups })
    } finally {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
    return $availableResourceGroups
}
Export-ModuleMember -Function Get-SreResourceGroups


# Show SRE or SHM full config
# ---------------------
function Show-FullConfig {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID")]
        [string]$shmId,
        [Parameter(Mandatory = $false, HelpMessage = "Enter SRE ID")]
        [string]$sreId
    )
    # Generate and return the full config for the SHM or SRE
    if ($sreId -eq "") {
        $config = Get-ShmConfig -shmId $shmId
    } else {
        $config = Get-SreConfig -shmId ${shmId} -sreId ${sreId}
    }
    Write-Output ($config | ConvertTo-Json -Depth 99)
}
Export-ModuleMember -Function Show-FullConfig
