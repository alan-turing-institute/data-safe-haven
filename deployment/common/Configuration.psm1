Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.RecoveryServices -ErrorAction Stop # Note that this contains TimeZoneConverter
Import-Module Az.Resources -ErrorAction Stop
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop
Import-Module $PSScriptRoot/Networking -ErrorAction Stop
Import-Module $PSScriptRoot/Security -ErrorAction Stop


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

    # Monitoring config
    # -----------------
    $shm.monitoring = [ordered]@{
        rg                = "$($shm.rgPrefix)_MONITORING".ToUpper()
        automationAccount = @{
            name = "shm-$($shm.id)-automation".ToLower()
        }
        loggingWorkspace  = @{
            name = "shm-$($shm.id)-loganalytics".ToLower()
        }
        privatelink       = @{
            name = "shm-$($shm.id)-privatelinkscope".ToLower()
        }
        updateServers     = @{
            linux   = (
                @("91.189.91.38", "91.189.91.39", "185.125.190.36", "185.125.190.39") + # archive.ubuntu.com, security.ubuntu.com
                @("51.132.212.186") # azure.archive.ubuntu.com
            )
            windows = (
                @("96.17.178.173", "96.17.178.180") + # au.download.windowsupdate.com
                @("8.238.55.126", "8.238.60.254", "8.250.17.254", "8.238.5.126", "8.238.9.126") + # ctldl.windowsupdate.com
                @("93.184.221.240") + # download.windowsupdate.com
                @("52.167.107.72") + # eus2-jobruntimedata-prod-su1.azure-automation.net
                @("20.83.81.160", "20.62.190.187") + # fe2cr.update.microsoft.com
                @("20.49.150.241") + # settings-win.data.microsoft.com
                @("52.152.110.14") + # slscr.update.microsoft.com
                @("20.189.173.22") + # umwatson.events.data.microsoft.com
                @("13.89.179.9") # v10.events.data.microsoft.com
            )
        }
    }

    # Logging config
    # --------------
    $shm.logging = [ordered]@{ # TODO move these to the monitoring config
        rg            = "$($shm.rgPrefix)_LOGGING".ToUpper()
        workspaceName = "shm$($shm.id)loganalytics".ToLower()
    }

    # Network config
    # --------------
    # Deconstruct base address prefix to allow easy construction of IP based parameters
    $shmPrefixOctets = $shmIpPrefix.Split(".")
    $shmBasePrefix = "$($shmPrefixOctets[0]).$($shmPrefixOctets[1])"
    $shmThirdOctet = ([int]$shmPrefixOctets[2])
    $shm.network = [ordered]@{
        vnet            = [ordered]@{
            rg      = "$($shm.rgPrefix)_NETWORKING".ToUpper()
            name    = "VNET_SHM_$($shm.id)".ToUpper()
            cidr    = "${shmBasePrefix}.${shmThirdOctet}.0/21"
            subnets = [ordered]@{
                identity   = [ordered]@{
                    name = "IdentitySubnet"
                    cidr = "${shmBasePrefix}.${shmThirdOctet}.0/24"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_IDENTITY".ToUpper()
                        rules = "shm-nsg-rules-identity.json"
                    }
                }
                monitoring = [ordered]@{
                    name = "MonitoringSubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 1).0/24"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_MONITORING".ToUpper()
                        rules = "shm-nsg-rules-monitoring.json"
                    }
                }
                firewall   = [ordered]@{
                    # NB. The firewall subnet MUST be named 'AzureFirewallSubnet'. See https://docs.microsoft.com/en-us/azure/firewall/tutorial-firewall-deploy-portal
                    name = "AzureFirewallSubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 2).0/24"
                }
                gateway    = [ordered]@{
                    # NB. The Gateway subnet MUST be named 'GatewaySubnet'. See https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq#do-i-need-a-gatewaysubnet
                    name = "GatewaySubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 7).0/24"
                }
            }
        }
        vpn             = [ordered]@{
            cidr = "172.16.201.0/24" # NB. this must not overlap with the VNet that the VPN gateway is part of
        }
        repositoryVnets = [ordered]@{}
        mirrorVnets     = [ordered]@{}
    }
    foreach ($tier in @(2, 3)) {
        $shmRepositoryPrefix = "10.30.$($tier-1)"
        # TODO: $tier-1 is for backwards compatibility and may be removed in a major version update
        $shm.network.repositoryVnets["tier${tier}"] = [ordered]@{
            name    = "VNET_SHM_$($shm.id)_NEXUS_REPOSITORY_TIER_${tier}".ToUpper()
            cidr    = "${shmRepositoryPrefix}.0/24"
            subnets = [ordered]@{
                repository = [ordered]@{
                    name = "RepositoryTier${tier}Subnet"
                    cidr = "${shmRepositoryPrefix}.0/24"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_NEXUS_REPOSITORY_TIER_${tier}".ToUpper()
                        rules = "shm-nsg-rules-nexus-tier${tier}.json"
                    }
                }
            }
        }
    }
    # Set package mirror networking information
    foreach ($tier in @(2, 3)) {
        $shmMirrorPrefix = "10.20.${tier}"
        $shm.network.mirrorVnets["tier${tier}"] = [ordered]@{
            name    = "VNET_SHM_$($shm.id)_PACKAGE_MIRRORS_TIER${tier}".ToUpper()
            cidr    = "${shmMirrorPrefix}.0/24"
            subnets = [ordered]@{
                external = [ordered]@{
                    name = "ExternalPackageMirrorsTier${tier}Subnet"
                    cidr = "${shmMirrorPrefix}.0/28"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_EXTERNAL_PACKAGE_MIRRORS_TIER${tier}".ToUpper()
                        rules = "shm-nsg-rules-external-mirrors-tier${tier}.json"
                    }
                }
                internal = [ordered]@{
                    name = "InternalPackageMirrorsTier${tier}Subnet"
                    cidr = "${shmMirrorPrefix}.16/28"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_INTERNAL_PACKAGE_MIRRORS_TIER${tier}".ToUpper()
                        rules = "shm-nsg-rules-internal-mirrors-tier${tier}.json"
                    }
                }
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
                type   = "Standard_LRS"
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
                type   = "Standard_LRS"
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

    # Nexus repository VM config
    $shm.repository = [ordered]@{}
    # --------------------------
    foreach ($tier in @(2, 3)) {
        $shm.repository["tier${tier}"] = [ordered]@{
            rg       = "$($shm.rgPrefix)_NEXUS_REPOSITORIES".ToUpper()
            vmSize   = "Standard_B2ms"
            diskType = "Standard_LRS"
            nexus    = [ordered]@{
                adminPasswordSecretName         = "shm-$($shm.id)-vm-admin-password-nexus-tier${tier}".ToLower()
                nexusAppAdminPasswordSecretName = "shm-$($shm.id)-nexus-repository-admin-password-tier${tier}".ToLower()
                ipAddress                       = "10.30.$($tier-1).10"
                # TODO: $tier-1 is for backwards compatibility and may be removed in a major version update
                vmName                          = "NEXUS-REPOSITORY-TIER-${tier}"
            }
        }
    }

    # Package mirror config
    # ---------------------
    $shm.mirrors = [ordered]@{
        rg       = "$($shm.rgPrefix)_PKG_MIRRORS".ToUpper()
        vmSize   = "Standard_B2ms"
        diskType = "Standard_LRS"
        pypi     = [ordered]@{
            tier2 = [ordered]@{ diskSize = 8192 }
            tier3 = [ordered]@{ diskSize = 1024 }
        }
        cran     = [ordered]@{
            tier2 = [ordered]@{ diskSize = 128 }
            tier3 = [ordered]@{ diskSize = 32 }
        }
    }
    # Set password secret name and IP address for each mirror
    foreach ($tier in @(2, 3)) {
        foreach ($direction in @("internal", "external")) {
            # Please note that each mirror type must have a distinct ipOffset in the range 4-15
            foreach ($typeOffset in @(("pypi", 4), ("cran", 5))) {
                $shm.mirrors[$typeOffset[0]]["tier${tier}"][$direction] = [ordered]@{
                    adminPasswordSecretName = "shm-$($shm.id)-vm-admin-password-$($typeOffset[0])-${direction}-mirror-tier-${tier}".ToLower()
                    ipAddress               = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.mirrorVnets["tier${tier}"].subnets[$direction].cidr -Offset $typeOffset[1]
                    vmName                  = "$($typeOffset[0])-${direction}-MIRROR-TIER-${tier}".ToUpper()
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
    $nexusDefault = ($sreConfigBase.tier -eq "2") ? $true : $false # Nexus is the default for tier-2 SREs
    $config = [ordered]@{
        shm = Get-ShmConfig -shmId $sreConfigBase.shmId
        sre = [ordered]@{
            id               = $sreConfigBase.sreId | Limit-StringLength -MaximumLength 7 -FailureIsFatal
            rgPrefix         = $sreConfigBase.overrides.sre.rgPrefix ? $sreConfigBase.overrides.sre.rgPrefix : "RG_SHM_$($sreConfigBase.shmId)_SRE_$($sreConfigBase.sreId)".ToUpper()
            nsgPrefix        = $sreConfigBase.overrides.sre.nsgPrefix ? $sreConfigBase.overrides.sre.nsgPrefix : "NSG_SHM_$($sreConfigBase.shmId)_SRE_$($sreConfigBase.sreId)".ToUpper()
            shortName        = "sre-$($sreConfigBase.sreId)".ToLower()
            subscriptionName = $sreConfigBase.subscriptionName
            tier             = $sreConfigBase.tier
            nexus            = $sreConfigBase.nexus -is [bool] ? $sreConfigBase.nexus : $nexusDefault
            remoteDesktop    = [ordered]@{
                provider = $sreConfigBase.remoteDesktopProvider
            }
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
            account = [ordered]@{
                name               = "${sreStoragePrefix}artifacts${sreStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
                storageKind        = "BlobStorage"
                performance        = "Standard_LRS" # see https://docs.microsoft.com/en-us/azure/storage/common/storage-account-overview#types-of-storage-accounts for allowed types
                accessTier         = "Cool"
                allowedIpAddresses = $sreConfigBase.deploymentIpAddresses ? @($sreConfigBase.deploymentIpAddresses) : "any"
            }
            rg      = $storageRg
        }
        bootdiagnostics = [ordered]@{
            accountName = "${sreStoragePrefix}bootdiags${sreStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
            rg          = $storageRg
        }
        userdata        = [ordered]@{
            account    = [ordered]@{
                name        = "${sreStoragePrefix}userdata${sreStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
                storageKind = "FileStorage"
                performance = "Premium_LRS" # see https://docs.microsoft.com/en-us/azure/storage/common/storage-account-overview#types-of-storage-accounts for allowed types
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
                storageKind        = "BlobStorage"
                performance        = "Standard_LRS" # see https://docs.microsoft.com/en-us/azure/storage/common/storage-account-overview#types-of-storage-accounts for allowed types
                accessTier         = "Hot"
                allowedIpAddresses = $sreConfigBase.dataAdminIpAddresses ? @($sreConfigBase.dataAdminIpAddresses) : $shm.srdImage.build.nsg.allowedIpAddresses
            }
            containers = [ordered]@{
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
                    type   = "Standard_LRS"
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
                    type   = "Standard_LRS"
                }
                os   = [ordered]@{
                    sizeGb = "128"
                    type   = "Standard_LRS"
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
                    type   = "Standard_LRS"
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
        $config.sre.remoteDesktop.networkRules.allowedSources = $sreConfigBase.inboundAccessFrom
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
        $config.sre.remoteDesktop.networkRules.outboundInternet = $sreConfigBase.outboundInternet
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
            osVersion               = "20.04-LTS"
            disks                   = [ordered]@{
                data = [ordered]@{
                    sizeGb = "512"
                    type   = "Standard_LRS"
                }
                os   = [ordered]@{
                    sizeGb = "32"
                    type   = "Standard_LRS"
                }
            }
        }
        codimd = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-codimd"
            hostname                = "CODIMD"
            vmSize                  = "Standard_D2s_v3"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.webapps.cidr -Offset 6
            osVersion               = "20.04-LTS"
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
                    type   = "Standard_LRS"
                }
                os   = [ordered]@{
                    sizeGb = "32"
                    type   = "Standard_LRS"
                }
            }
        }
        gitlab = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-gitlab"
            hostname                = "GITLAB"
            vmSize                  = "Standard_D2s_v3"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.webapps.cidr -Offset 5
            rootPasswordSecretName  = "$($config.sre.shortName)-other-gitlab-root-password"
            osVersion               = "20.04-LTS"
            disks                   = [ordered]@{
                data = [ordered]@{
                    sizeGb = "512"
                    type   = "Standard_LRS"
                }
                os   = [ordered]@{
                    sizeGb = "32"
                    type   = "Standard_LRS"
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
        PostgreSQL = @{port = "5432"; prefix = "PSTGRS"; sku = "20.04-LTS" }
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
                    type   = "Standard_LRS"
                }
                os   = [ordered]@{
                    sizeGb = "128"
                    type   = "Standard_LRS"
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
                type   = "Standard_LRS"
            }
            scratch = [ordered]@{
                sizeGb = "1024"
                type   = "Standard_LRS"
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
        # All Nexus repositories are accessed over the same port (currently 80)
        if ($config.sre.nexus) {
            $nexus_port = 80
            if ([int]$config.sre.tier -gt 3) {
                Add-LogMessage -Level Fatal "Nexus repositories cannot currently be used for tier $($config.sre.tier) SREs!"
            }
            $cranUrl = "http://$($config.shm.repository["tier$($config.sre.tier)"].nexus.ipAddress):${nexus_port}/repository/cran-proxy"
            $pypiUrl = "http://$($config.shm.repository["tier$($config.sre.tier)"].nexus.ipAddress):${nexus_port}/repository/pypi-proxy"
            $repositoryVNetName = $config.shm.network.repositoryVnets["tier$($config.sre.tier)"].name
            $repositoryVNetCidr = $config.shm.network.repositoryVnets["tier$($config.sre.tier)"].cidr
        # Package mirrors use port 3128 (PyPI) or port 80 (CRAN)
        } else {
            $cranUrl = "http://" + $($config.shm.mirrors.cran["tier$($config.sre.tier)"].internal.ipAddress)
            $pypiUrl = "http://" + $($config.shm.mirrors.pypi["tier$($config.sre.tier)"].internal.ipAddress) + ":3128"
            $repositoryVNetName = $config.shm.network.mirrorVnets["tier$($config.sre.tier)"].name
            $repositoryVNetCidr = $config.shm.network.mirrorVnets["tier$($config.sre.tier)"].cidr
        }
    }
    # We want to extract the hostname from PyPI URLs in any of the following forms
    # 1. http://10.20.2.20:3128                      => 10.20.2.20
    # 2. https://pypi.org                            => pypi.org
    # 3. http://10.30.1.10:80/repository/pypi-proxy  => 10.30.1.10
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
