Import-Module $PSScriptRoot/DataStructures.psm1
Import-Module $PSScriptRoot/Logging.psm1
Import-Module $PSScriptRoot/Networking.psm1
Import-Module $PSScriptRoot/Security.psm1


# Add a new SRE configuration
# ---------------------------
function Add-SreConfig {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
        [string]$configId
    )
    Add-LogMessage -Level Info "Generating/updating config file for '$configId'"

    # Import minimal management config parameters from JSON config file - we can derive the rest from these
    $sreConfigBase = Get-ConfigFile -configType "sre" -configLevel "core" -configName $configId

    # Ensure that naming structure is being adhered to
    if ($configId -ne "$($sreConfigBase.shmId)$($sreConfigBase.sreId)") {
        Add-LogMessage -Level Fatal "Config file '$configId' should be using '$($sreConfigBase.shmId)$($sreConfigBase.sreId)' as its identifier!"
    }

    # Secure research environment config
    # ----------------------------------
    $config = [ordered]@{
        shm = Get-ShmFullConfig -shmId $sreConfigBase.shmId
        sre = [ordered]@{
            azureAdminGroupName = $sreConfigBase.azureAdminGroupName
            id = $sreConfigBase.sreId | Limit-StringLength 7 -FailureIsFatal
            rgPrefix = $sreConfigBase.overrides.sre.rgPrefix ? $sreConfigBase.overrides.sre.rgPrefix : "RG_SRE_$($sreConfigBase.sreId)".ToUpper()
            nsgPrefix = $sreConfigBase.overrides.sre.nsgPrefix ? $sreConfigBase.overrides.sre.nsgPrefix : "NSG_SRE_$($sreConfigBase.sreId)".ToUpper()
            shortName = "sre-$($sreConfigBase.sreId)".ToLower()
            subscriptionName = $sreConfigBase.subscriptionName
            tier = $sreConfigBase.tier
        }
    }
    $config.sre.location = $config.shm.location

    # Ensure that this tier is supported
    if (-not @("0", "1", "2", "3").Contains($config.sre.tier)) {
        Add-LogMessage -Level Fatal "Tier '$($config.sre.tier)' not supported (NOTE: Tier must be provided as a string in the core SRE config.)"
    }

    # Domain config
    # -------------
    $config.sre.domain = [ordered]@{
        dn = "DC=$($sreConfigBase.domain.Replace('.',',DC='))"
        fqdn = $sreConfigBase.domain
        netbiosName = $($config.sre.id).ToUpper() | Limit-StringLength 15 -FailureIsFatal
    }
    $config.sre.domain.securityGroups = [ordered]@{
        dataAdministrators = [ordered]@{ name = "SG $($config.sre.domain.netbiosName) Data Administrators" }
        systemAdministrators = [ordered]@{ name = "SG $($config.sre.domain.netbiosName) System Administrators" }
        researchUsers = [ordered]@{ name = "SG $($config.sre.domain.netbiosName) Research Users" }
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
            rg = "$($config.sre.rgPrefix)_NETWORKING".ToUpper()
            name = "VNET_SRE_$($config.sre.id)".ToUpper()
            cidr = "${sreBasePrefix}.${sreThirdOctet}.0/21"
            subnets = [ordered]@{
                identity = [ordered]@{
                    name = "IdentitySubnet"
                    cidr = "${sreBasePrefix}.${sreThirdOctet}.0/24"
                }
                rds = [ordered]@{
                    name = "RDSSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 1).0/24"
                }
                data = [ordered]@{
                    name = "SharedDataSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 2).0/24"
                }
                databases = [ordered]@{
                    name = "DatabasesSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 3).0/24"
                    nsg = "databases"
                }
            }
        }
        nsg = [ordered]@{
            data = [ordered]@{}
            databases = [ordered]@{
                name = "$($config.sre.nsgPrefix)_DATABASES".ToUpper()
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
    $storageRg = "$($config.sre.rgPrefix)_ARTIFACTS".ToUpper()
    $sreStorageSuffix = New-RandomLetters -SeedPhrase "$($config.sre.subscriptionName)$($config.sre.id)"
    $config.sre.storage = [ordered]@{
        artifacts = [ordered]@{
            accountName = "sre$($config.sre.id)artifacts${sreStorageSuffix}".ToLower() | Limit-StringLength 24 -Silent
            rg = $storageRg
        }
        bootdiagnostics = [ordered]@{
            accountName = "sre$($config.sre.id)bootdiags${sreStorageSuffix}".ToLower() | Limit-StringLength 24 -Silent
            rg = $storageRg
        }
        data = [ordered]@{
            ingress = [ordered]@{
                accountName   = "sre$($config.sre.id)ingress${sreStorageSuffix}".ToLower() | Limit-StringLength 24 -Silent
                containerName = "ingress"
            }
            egress = [ordered]@{
                accountName   = "sre$($config.sre.id)egress${sreStorageSuffix}".ToLower() | Limit-StringLength 24 -Silent
                containerName = "ingress"
            }
        }
    }

    # Secrets config
    # --------------
    $config.sre.keyVault = [ordered]@{
        name = "kv-$($config.shm.id)-sre-$($config.sre.id)".ToLower() | Limit-StringLength 24
        rg = "$($config.sre.rgPrefix)_SECRETS".ToUpper()
        secretNames = [ordered]@{
            adminUsername = "$($config.sre.shortName)-vm-admin-username"
            letsEncryptCertificate = "$($config.sre.shortName)-lets-encrypt-certificate"
            npsSecret = "$($config.sre.shortName)-other-nps-secret"
        }
    }

    # SRE users
    # ---------
    $config.sre.users = [ordered]@{
        serviceAccounts = [ordered]@{
            ldapSearch = [ordered]@{
                name = "$($config.sre.domain.netbiosName) LDAP Search Service Account"
                samAccountName = "$($config.sre.id)ldapsearch".ToLower() | Limit-StringLength 20
                passwordSecretName = "$($config.sre.shortName)-other-service-account-password-ldap-search"
            }
            postgres = [ordered]@{
                name = "$($config.sre.domain.netbiosName) Postgres DB Service Account"
                samAccountName = "$($config.sre.id)dbpostgres".ToLower() | Limit-StringLength 20
                passwordSecretName = "$($config.sre.shortName)-db-service-account-password-postgres"
            }
            datamount = [ordered]@{
                name = "$($config.sre.domain.netbiosName) Data Mount Service Account"
                samAccountName = "$($config.sre.id)datamount".ToLower() | Limit-StringLength 20
                passwordSecretName = "$($config.sre.shortName)-other-service-account-password-datamount"
            }
        }
    }

    # RDS Servers
    # -----------
    $config.sre.rds = [ordered]@{
        rg = "$($config.sre.rgPrefix)_RDS".ToUpper()
        gateway = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-rds-gateway"
            vmName = "RDG-SRE-$($config.sre.id)".ToUpper() | Limit-StringLength 15
            vmSize = "Standard_DS2_v2"
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.rds.cidr -Offset 4
            nsg = "$($config.sre.nsgPrefix)_RDS_SERVER".ToUpper()
            networkRules = [ordered]@{}
            disks = [ordered]@{
                data1 = [ordered]@{
                    sizeGb = "1023"
                    type = "Standard_LRS"
                }
                data2 = [ordered]@{
                    sizeGb = "1023"
                    type = "Standard_LRS"
                }
                os = [ordered]@{
                    sizeGb = "128"
                    type = "Standard_LRS"
                }
            }
        }
        appSessionHost = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-rds-sh1"
            vmName = "APP-SRE-$($config.sre.id)".ToUpper() | Limit-StringLength 15
            vmSize = "Standard_DS2_v2"
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.rds.cidr -Offset 5
            nsg = "$($config.sre.nsgPrefix)_RDS_SESSION_HOSTS".ToUpper()
            disks = [ordered]@{
                os = [ordered]@{
                    sizeGb = "128"
                    type = "Standard_LRS"
                }
            }
        }
    }
    # Construct the hostname and FQDN for each VM
    foreach ($server in $config.sre.rds.Keys) {
        if ($config.sre.rds[$server] -IsNot [System.Collections.Specialized.OrderedDictionary]) { continue }
        $config.sre.rds[$server].hostname = $config.sre.rds[$server].vmName
        $config.sre.rds[$server].fqdn = "$($config.sre.rds[$server].vmName).$($config.shm.domain.fqdn)"
    }
    # Set which IPs can access the Safe Haven: if 'default' is given then apply sensible defaults
    if ($sreConfigBase.inboundAccessFrom -eq "default") {
        if (@("3", "4").Contains($config.sre.tier)) {
            $config.sre.rds.gateway.networkRules.allowedSources = "193.60.220.240"
        } elseif ($config.sre.tier -eq "2") {
            $config.sre.rds.gateway.networkRules.allowedSources = "193.60.220.253"
        } elseif (@("0", "1").Contains($config.sre.tier)) {
            $config.sre.rds.gateway.networkRules.allowedSources = "Internet"
        }
    } elseif ($sreConfigBase.inboundAccessFrom -eq "anywhere") {
        $config.sre.rds.gateway.networkRules.allowedSources = "Internet"
    } else {
        $config.sre.rds.gateway.networkRules.allowedSources = $sreConfigBase.inboundAccessFrom
    }
    # Set whether internet access is allowed: if 'default' is given then apply sensible defaults
    if ($sreConfigBase.outboundInternetAccess -eq "default") {
        if (@("2", "3", "4").Contains($config.sre.tier)) {
            $config.sre.rds.gateway.networkRules.outboundInternet = "Deny"
        } elseif (@("0", "1").Contains($config.sre.tier)) {
            $config.sre.rds.gateway.networkRules.outboundInternet = "Allow"
        }
    } elseif (@("no", "deny", "forbid").Contains($($sreConfigBase.outboundInternetAccess).ToLower())) {
        $config.sre.rds.gateway.networkRules.outboundInternet = "Deny"
    } elseif (@("yes", "allow", "permit").Contains($($sreConfigBase.outboundInternetAccess).ToLower())) {
        $config.sre.rds.gateway.networkRules.outboundInternet = "Allow"
    } else {
        $config.sre.rds.gateway.networkRules.outboundInternet = $sreConfigBase.outboundInternet
    }


    # Data server
    # -----------
    $hostname = "DAT-SRE-$($config.sre.id)".ToUpper() | Limit-StringLength 15
    $config.sre.dataserver = [ordered]@{
        adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-dataserver"
        rg = "$($config.sre.rgPrefix)_DATA".ToUpper()
        nsg = "$($config.sre.nsgPrefix)_DATA".ToUpper()
        vmName = $hostname
        vmSize = "Standard_D2s_v3"
        hostname = $hostname
        fqdn = "${hostname}.$($config.shm.domain.fqdn)"
        ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.data.cidr -Offset 4
        disks = [ordered]@{
            egress = [ordered]@{
                sizeGb = "512"
                type = "Standard_LRS"
            }
            ingress = [ordered]@{
                sizeGb = "512"
                type = "Standard_LRS"
            }
            shared = [ordered]@{
                sizeGb = "512"
                type = "Standard_LRS"
            }
        }
    }

    # HackMD and Gitlab servers
    # -------------------------
    $config.sre.webapps = [ordered]@{
        rg = "$($config.sre.rgPrefix)_WEBAPPS".ToUpper()
        nsg = "$($config.sre.nsgPrefix)_WEBAPPS".ToUpper()
        gitlab = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-gitlab"
            vmName = "GITLAB-SRE-$($config.sre.id)".ToUpper()
            vmSize = "Standard_D2s_v3"
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.data.cidr -Offset 5
            rootPasswordSecretName = "$($config.sre.shortName)-other-gitlab-root-password"
            disks = [ordered]@{
                data = [ordered]@{
                    sizeGb = "750"
                    type = "Standard_LRS"
                }
                os = [ordered]@{
                    sizeGb = "50"
                    type = "Standard_LRS"
                }
            }
        }
        hackmd = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-hackmd"
            vmName = "HACKMD-SRE-$($config.sre.id)".ToUpper()
            vmSize = "Standard_D2s_v3"
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.data.cidr -Offset 6
            disks = [ordered]@{
                os = [ordered]@{
                    sizeGb = "750"
                    type = "Standard_LRS"
                }
            }
        }
    }
    # Construct the hostname and FQDN for each VM
    foreach ($server in $config.sre.webapps.Keys) {
        if ($config.sre.webapps[$server] -IsNot [System.Collections.Specialized.OrderedDictionary]) { continue }
        $config.sre.webapps[$server].hostname = $config.sre.webapps[$server].vmName
        $config.sre.webapps[$server].fqdn = "$($config.sre.webapps[$server].vmName).$($config.shm.domain.fqdn)"
    }


    # Databases
    # ---------
    $config.sre.databases = [ordered]@{
        rg = "$($config.sre.rgPrefix)_DATABASES".ToUpper()
    }
    $dbConfig = @{
        MSSQL = @{port = "1433"; prefix = "MSSQL"; sku = "sqldev"}
        PostgreSQL = @{port = "5432"; prefix = "PSTGRS"; sku = "18.04-LTS"}
    }
    $ipOffset = 4
    foreach ($databaseType in $sreConfigBase.databases) {
        if (-not @($dbConfig.Keys).Contains($databaseType)) {
            Add-LogMessage -Level Fatal "Database type '$databaseType' was not recognised!"
        }
        $config.sre.databases["db$($databaseType.ToLower())"] = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-$($databaseType.ToLower())"
            dbAdminUsernameSecretName = "$($config.sre.shortName)-db-admin-username-$($databaseType.ToLower())"
            dbAdminPasswordSecretName = "$($config.sre.shortName)-db-admin-password-$($databaseType.ToLower())"
            vmName = "$($dbConfig[$databaseType].prefix)-$($config.sre.id)".ToUpper() | Limit-StringLength 15
            type = $databaseType
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.databases.cidr -Offset $ipOffset
            port = $dbConfig[$databaseType].port
            sku = $dbConfig[$databaseType].sku
            subnet = "databases"
            vmSize = "Standard_DS2_v2"
            disks = [ordered]@{
                data = [ordered]@{
                    sizeGb = "1024"
                    type = "Standard_LRS"
                }
                os = [ordered]@{
                    sizeGb = "128"
                    type = "Standard_LRS"
                }
            }
        }
        if ($databaseType -eq "MSSQL") { $config.sre.databases["db$($databaseType.ToLower())"]["enableSSIS"] = $true }
        $ipOffset += 1
    }

    # Compute VMs
    # -----------
    $config.sre.dsvm = [ordered]@{
        adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-compute"
        rg = "$($config.sre.rgPrefix)_COMPUTE".ToUpper()
        nsg = "$($config.sre.nsgPrefix)_COMPUTE".ToUpper()
        deploymentNsg = "$($config.sre.nsgPrefix)_COMPUTE_DEPLOYMENT".ToUpper()
        vmImage = [ordered]@{
            subscription = $config.shm.dsvmImage.subscription
            rg = $config.shm.dsvmImage.gallery.rg
            gallery = $config.shm.dsvmImage.gallery.sig
            type = $sreConfigBase.computeVmImageType
            version = $sreConfigBase.computeVmImageVersion
        }
        vmSizeDefault = "Standard_D2s_v3"
        disks = [ordered]@{
            home = [ordered]@{
                sizeGb = "128"
                type = "Standard_LRS"
            }
            os = [ordered]@{
                sizeGb = "default"
                type = "Standard_LRS"
            }
            scratch = [ordered]@{
                sizeGb = "512"
                type = "Standard_LRS"
            }
        }
    }
    $config.shm.Remove("dsvmImage")

    # Apply overrides (if any exist)
    # ------------------------------
    if ($sreConfigBase.overrides) {
        Copy-HashtableOverrides -Source $sreConfigBase.overrides -Target $config
    }

    # Write output to file
    # --------------------
    $jsonOut = (ConvertTo-SortedHashtable -Sortable $config | ConvertTo-Json -Depth 10)
    $sreFullConfigPath = Join-Path $(Get-ConfigRootDir) "full" "sre_${configId}_full_config.json"
    Out-File -FilePath $sreFullConfigPath -Encoding "UTF8" -InputObject $jsonOut
    Add-LogMessage -Level Info "Wrote config file to '$sreFullConfigPath'"
}
Export-ModuleMember -Function Add-SreConfig


# Get root directory for configuration files
# ------------------------------------------
function Get-ConfigRootDir {
    try {
        return Join-Path (Get-Item $PSScriptRoot).Parent.Parent.FullName "environment_configs" -Resolve -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        Add-LogMessage -Level Fatal "Could not find the configuration file root directory!"
    }
}


# Load a config file into a hashtable
# -----------------------------------
function Get-ConfigFile {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Config type ('sre' or 'shm')")]
        [ValidateSet("sre", "shm")]
        $configType,
        [Parameter(Mandatory = $true, HelpMessage = "Config level ('core' or 'full')")]
        [ValidateSet("core", "full")]
        $configLevel,
        [Parameter(Mandatory = $true, HelpMessage = "Name that identifies this config file (ie. <SHM ID> or <SHM ID><SRE ID>))")]
        $configName
    )
    $configFilename = "${configType}_${configName}_${configLevel}_config.json"
    try {
        $configPath = Join-Path $(Get-ConfigRootDir) $configLevel $configFilename -Resolve -ErrorAction Stop
        $configJson = Get-Content -Path $configPath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    } catch [System.Management.Automation.ItemNotFoundException] {
        Add-LogMessage -Level Fatal "Could not find a config file named '$configFilename'..."
    } catch [System.ArgumentException] {
        Add-LogMessage -Level Fatal "'$configPath' is not a valid JSON config file..."
    }
    return $configJson
}


# Get SHM configuration
# ---------------------
function Get-ShmFullConfig {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID ('test' or 'prod')")]
        $shmId
    )
    # Import minimal management config parameters from JSON config file - we can derive the rest from these
    $shmConfigBase = Get-ConfigFile -configType "shm" -configLevel "core" -configName $shmId
    $shmIpPrefix = "10.0.0"  # This does not need to be user-configurable. Different SHMs can share the same address space as they are never peered.

    # Safe Haven management config
    # ----------------------------
    $shm = [ordered]@{
        azureAdminGroupName = $shmConfigBase.azureAdminGroupName
        id = $shmConfigBase.shmId
        location = $shmConfigBase.location
        name = $shmConfigBase.name
        organisation = $shmConfigBase.organisation
        rgPrefix = $shmConfigBase.overrides.rgPrefix ? $shmConfigBase.overrides.rgPrefix : "RG_SHM_$($shmConfigBase.shmId)".ToUpper()
        nsgPrefix = $shmConfigBase.overrides.nsgPrefix ? $shmConfigBase.overrides.nsgPrefix : "NSG_SHM_$($shmConfigBase.shmId)".ToUpper()
        subscriptionName = $shmConfigBase.subscriptionName
    }

    # DSVM build images
    # -----------------
    $dsvmImageStorageSuffix = New-RandomLetters -SeedPhrase $shmConfigBase.images.subscriptionName
    # Since an ImageGallery cannot be moved once created, we must ensure that the location parameter matches any gallery that already exists
    $originalContext = Get-AzContext
    $null = Set-AzContext -SubscriptionId $shmConfigBase.images.subscriptionName
    $locations = Get-AzResource | Where-Object { $_.ResourceGroupName -like "RG_SH_*" } | ForEach-Object { $_.Location } | Sort-Object | Get-Unique
    if ($locations.Count -gt 1) {
        Add-LogMessage -Level Fatal "Image building resources found in multiple locations: ${locations}!"
    } elseif ($locations.Count -eq 1) {
        if ($shmConfigBase.images.location -ne $locations) {
            Add-LogMessage -Level Fatal "Image building location ($($shmConfigBase.images.location)) must be set to ${locations}!"
        }
    }
    $null = Set-AzContext -Context $originalContext
    # Construct build images config
    $shm.dsvmImage = [ordered]@{
        subscription = $shmConfigBase.images.subscriptionName
        location = $shmConfigBase.images.location
        bootdiagnostics = [ordered]@{
            rg = "RG_SH_BOOT_DIAGNOSTICS"
            accountName = "buildimgbootdiags${dsvmImageStorageSuffix}".ToLower() | Limit-StringLength 24 -Silent
        }
        build = [ordered]@{
            rg = "RG_SH_BUILD_CANDIDATES"
            nsg = [ordered]@{ name = "NSG_IMAGE_BUILD" }
            vnet = [ordered]@{
                name = "VNET_IMAGE_BUILD"
                cidr = "10.48.0.0/16"
            }
            subnet = [ordered]@{
                name = "ImageBuildSubnet"
                cidr = "10.48.0.0/24"
            }
            # Only the R-package installation is parallelisable and 8 GB of RAM is sufficient
            # We want a compute-optimised VM, since per-core performance is the bottleneck
            vm = [ordered]@{
                diskSizeGb = 64
                size = "Standard_F4s_v2"
            }
        }
        gallery = [ordered]@{
            rg = "RG_SH_IMAGE_GALLERY"
            sig = "SAFE_HAVEN_COMPUTE_IMAGES"
            imageMajorVersion = 0
            imageMinorVersion = 3
        }
        images = [ordered]@{
            rg = "RG_SH_IMAGE_STORAGE"
        }
        keyVault = [ordered]@{
            rg = "RG_SH_SECRETS"
            name = "kv-shm-$($shm.id)-dsvm-imgs".ToLower() | Limit-StringLength 24
        }
        network = [ordered]@{
            rg = "RG_SH_NETWORKING"
        }
    }

    # Domain config
    # -------------
    $shm.domain = [ordered]@{
        fqdn = $shmConfigBase.domain
        netbiosName = ($shmConfigBase.netbiosName ? $shmConfigBase.netbiosName : $shm.id).ToUpper() | Limit-StringLength 15 -FailureIsFatal
        dn = "DC=$(($shmConfigBase.domain).Replace('.',',DC='))"
        ous = [ordered]@{
            dataServers = [ordered]@{ name = "Secure Research Environment Data Servers" }
            linuxServers = [ordered]@{ name = "Secure Research Environment Linux Servers" }
            rdsGatewayServers = [ordered]@{ name = "Secure Research Environment RDS Gateway Servers" }
            rdsSessionServers = [ordered]@{ name = "Secure Research Environment RDS Session Servers" }
            researchUsers = [ordered]@{ name = "Safe Haven Research Users" }
            securityGroups = [ordered]@{ name = "Safe Haven Security Groups" }
            serviceAccounts = [ordered]@{ name = "Safe Haven Service Accounts" }
            identityServers = [ordered]@{ name = "Safe Haven Identity Servers" }
        }
    }
    foreach ($ouName in $shm.domain.ous.Keys) {
        $shm.domain.ous[$ouName].path = "OU=$($shm.domain.ous[$ouName].name),$($shm.domain.dn)"
    }
    # Security groups
    $shm.domain.securityGroups = [ordered]@{
        computerManagers = [ordered]@{ name = "SG Safe Haven Computer Management Users" }
        serverAdmins = [ordered]@{ name = "SG Safe Haven Server Administrators" }
    }
    foreach ($groupName in $shm.domain.securityGroups.Keys) {
        $shm.domain.securityGroups[$groupName].description = $shm.domain.securityGroups[$groupName].name
    }

    # Logging config
    # --------------
    $shm.logging = [ordered]@{
        rg = "$($shm.rgPrefix)_LOGGING".ToUpper()
        workspaceName = "shm$($shm.id)loganalytics${storageSuffix}".ToLower()
    }

    # Network config
    # --------------
    # Deconstruct base address prefix to allow easy construction of IP based parameters
    $shmPrefixOctets = $shmIpPrefix.Split(".")
    $shmBasePrefix = "$($shmPrefixOctets[0]).$($shmPrefixOctets[1])"
    $shmThirdOctet = ([int]$shmPrefixOctets[2])
    $shmMirrorPrefixes = @{2 = "10.20.2"; 3 = "10.20.3"}
    $shm.network = [ordered]@{
        vnet = [ordered]@{
            rg = "$($shm.rgPrefix)_NETWORKING".ToUpper()
            name = "VNET_SHM_$($shm.id)".ToUpper()
            cidr = "${shmBasePrefix}.${shmThirdOctet}.0/21"
            subnets = [ordered]@{
                identity = [ordered]@{
                    name = "IdentitySubnet"
                    cidr = "${shmBasePrefix}.${shmThirdOctet}.0/24"
                }
                web = [ordered]@{
                    name = "WebSubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 1).0/24"
                }
                firewall = [ordered]@{
                    # NB. The firewall subnet MUST be named 'AzureFirewallSubnet'. See https://docs.microsoft.com/en-us/azure/firewall/tutorial-firewall-deploy-portal
                    name = "AzureFirewallSubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 2).0/24"
                }
                gateway = [ordered]@{
                    # NB. The Gateway subnet MUST be named 'GatewaySubnet'. See https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq#do-i-need-a-gatewaysubnet
                    name = "GatewaySubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 7).0/24"
                }
            }
        }
        vpn = [ordered]@{
            cidr = "172.16.201.0/24" # NB. this must not overlap with the VNet that the VPN gateway is part of
        }
        mirrorVnets = [ordered]@{}
        nsg = [ordered]@{
            externalPackageMirrorsTier2 = [ordered]@{
                name = "$($shm.nsgPrefix)_EXTERNAL_PACKAGE_MIRRORS_TIER2".ToUpper()
            }
            externalPackageMirrorsTier3 = [ordered]@{
                name = "$($shm.nsgPrefix)_EXTERNAL_PACKAGE_MIRRORS_TIER3".ToUpper()
            }
            internalPackageMirrorsTier2 = [ordered]@{
                name = "$($shm.nsgPrefix)_INTERNAL_PACKAGE_MIRRORS_TIER2".ToUpper()
            }
            internalPackageMirrorsTier3 = [ordered]@{
                name = "$($shm.nsgPrefix)_INTERNAL_PACKAGE_MIRRORS_TIER3".ToUpper()
            }
        }
    }
    # Set package mirror networking information
    foreach ($tier in @(2, 3)) {
        $shm.network.mirrorVnets["tier${tier}"] = [ordered]@{
            name = "VNET_SHM_$($shm.id)_PACKAGE_MIRRORS_TIER${tier}".ToUpper()
            cidr = "$($shmMirrorPrefixes[$tier]).0/24"
            subnets = [ordered]@{
                external = [ordered]@{
                    name = "ExternalPackageMirrorsTier${tier}Subnet"
                    cidr = "$($shmMirrorPrefixes[$tier]).0/28"
                    nsg = "externalPackageMirrorsTier${tier}"
                }
                internal = [ordered]@{
                    name = "InternalPackageMirrorsTier${tier}Subnet"
                    cidr = "$($shmMirrorPrefixes[$tier]).16/28"
                    nsg = "internalPackageMirrorsTier${tier}"
                }
            }
        }
    }

    # Firewall config
    # ---------------
    $shm.firewall = [ordered]@{
        name = "FIREWALL-SHM-$($shm.id)".ToUpper()
        routeTableName = "ROUTE-TABLE-SHM-$($shm.id)".ToUpper()
    }

    # Secrets config
    # --------------
    $shm.keyVault = [ordered]@{
        rg = "$($shm.rgPrefix)_SECRETS".ToUpper()
        name = "kv-shm-$($shm.id)".ToLower() | Limit-StringLength 24
        secretNames = [ordered]@{
            aadEmergencyAdminUsername = "shm-$($shm.id)-aad-emergency-admin-username".ToLower()
            aadEmergencyAdminPassword = "shm-$($shm.id)-aad-emergency-admin-password".ToLower()
            buildImageAdminUsername = "shm-$($shm.id)-buildimage-admin-username".ToLower()
            buildImageAdminPassword = "shm-$($shm.id)-buildimage-admin-password".ToLower()
            domainAdminUsername = "shm-$($shm.id)-domain-admin-username".ToLower()
            domainAdminPassword = "shm-$($shm.id)-domain-admin-password".ToLower()
            vmAdminUsername = "shm-$($shm.id)-vm-admin-username".ToLower()
            vpnCaCertificate = "shm-$($shm.id)-vpn-ca-cert".ToLower()
            vpnCaCertificatePlain = "shm-$($shm.id)-vpn-ca-cert-plain".ToLower()
            vpnCaCertPassword = "shm-$($shm.id)-vpn-ca-cert-password".ToLower()
            vpnClientCertificate = "shm-$($shm.id)-vpn-client-cert".ToLower()
            vpnClientCertPassword = "shm-$($shm.id)-vpn-client-cert-password".ToLower()
        }
    }

    # SHM users
    # ---------
    $shm.users = [ordered]@{
        computerManagers = [ordered]@{
            identityServers = [ordered]@{
                name = "$($shm.domain.netbiosName) Identity Servers Manager"
                samAccountName = "$($shm.id)identitysrvrs".ToLower() | Limit-StringLength 20
                passwordSecretName = "shm-$($shm.id)-computer-manager-password-identity-servers".ToLower()
            }
            dataServers = [ordered]@{
                name = "$($shm.domain.netbiosName) Data Servers Manager"
                samAccountName = "$($shm.id)datasrvrs".ToLower() | Limit-StringLength 20
                passwordSecretName = "shm-$($shm.id)-computer-manager-password-data-servers".ToLower()
            }
            linuxServers = [ordered]@{
                name = "$($shm.domain.netbiosName) Linux Servers Manager"
                samAccountName = "$($shm.id)linuxsrvrs".ToLower() | Limit-StringLength 20
                passwordSecretName = "shm-$($shm.id)-computer-manager-password-linux-servers".ToLower()
            }
            rdsGatewayServers = [ordered]@{
                name = "$($shm.domain.netbiosName) RDS Gateway Manager"
                samAccountName = "$($shm.id)gatewaysrvrs".ToLower() | Limit-StringLength 20
                passwordSecretName = "shm-$($shm.id)-computer-manager-password-rds-gateway-servers".ToLower()
            }
            rdsSessionServers = [ordered]@{
                name = "$($shm.domain.netbiosName) RDS Session Servers Manager"
                samAccountName = "$($shm.id)sessionsrvrs".ToLower() | Limit-StringLength 20
                passwordSecretName = "shm-$($shm.id)-computer-manager-password-rds-session-servers".ToLower()
            }
        }
        serviceAccounts = [ordered]@{
            aadLocalSync = [ordered]@{
                name = "$($shm.domain.netbiosName) Local AD Sync Administrator"
                samAccountName = "$($shm.id)localadsync".ToLower() | Limit-StringLength 20
                passwordSecretName = "shm-$($shm.id)-aad-localsync-password".ToLower()
                usernameSecretName =  "shm-$($shm.id)-aad-localsync-username".ToLower()
            }
        }
    }

    # Domain controller config
    # ------------------------
    $hostname = "DC1-SHM-$($shm.id)".ToUpper() | Limit-StringLength 15
    $shm.dc = [ordered]@{
        rg = "$($shm.rgPrefix)_DC".ToUpper()
        vmName = $hostname
        vmSize = "Standard_D2s_v3"
        hostname = $hostname
        fqdn = "${hostname}.$($shm.domain.fqdn)"
        ip = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.vnet.subnets.identity.cidr -Offset 4
        external_dns_resolver = "168.63.129.16"  # https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
        safemodePasswordSecretName = "shm-$($shm.id)-vm-safemode-password-dc".ToLower()
        disks = [ordered]@{
            data = [ordered]@{
                sizeGb = "20"
                type = "Standard_LRS"
            }
            os = [ordered]@{
                sizeGb = "128"
                type = "Standard_LRS"
            }
        }
    }

    # Backup domain controller config
    # -------------------------------
    $hostname = "DC2-SHM-$($shm.id)".ToUpper() | Limit-StringLength 15
    $shm.dcb = [ordered]@{
        vmName = $hostname
        vmSize = "Standard_D2s_v3"
        hostname = $hostname
        fqdn = "${hostname}.$($shm.domain.fqdn)"
        ip = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.vnet.subnets.identity.cidr -Offset 5
        disks = [ordered]@{
            data = [ordered]@{
                sizeGb = "20"
                type = "Standard_LRS"
            }
            os = [ordered]@{
                sizeGb = "128"
                type = "Standard_LRS"
            }
        }
    }

    # NPS config
    # ----------
    $hostname = "NPS-SHM-$($shm.id)".ToUpper() | Limit-StringLength 15
    $shm.nps = [ordered]@{
        adminPasswordSecretName = "shm-$($shm.id)-vm-admin-password-nps".ToLower()
        rg = "$($shm.rgPrefix)_NPS".ToUpper()
        vmName = $hostname
        vmSize = "Standard_D2s_v3"
        hostname = $hostname
        ip = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.vnet.subnets.identity.cidr -Offset 6
        disks = [ordered]@{
            data = [ordered]@{
                sizeGb = "20"
                type = "Standard_LRS"
            }
            os = [ordered]@{
                sizeGb = "128"
                type = "Standard_LRS"
            }
        }
    }

    # Storage config
    # --------------
    $shmStorageSuffix = New-RandomLetters -SeedPhrase "$($shm.subscriptionName)$($shm.id)"
    $storageRg = "$($shm.rgPrefix)_ARTIFACTS".ToUpper()
    $shm.storage = [ordered]@{
        artifacts = [ordered]@{
            rg = $storageRg
            accountName = "shm$($shm.id)artifacts${shmStorageSuffix}".ToLower() | Limit-StringLength 24 -Silent
        }
        bootdiagnostics = [ordered]@{
            rg = $storageRg
            accountName = "shm$($shm.id)bootdiags${shmStorageSuffix}".ToLower() | Limit-StringLength 24 -Silent
        }
    }

    # DNS config
    # ----------
    $shm.dns = [ordered]@{
        subscriptionName = $shmConfigBase.dnsSubscriptionName
        rg = $shmConfigBase.dnsResourceGroupName
    }

    # Package mirror config
    # ---------------------
    $shm.mirrors = [ordered]@{
        rg = "$($shm.rgPrefix)_PKG_MIRRORS".ToUpper()
        vmSize = "Standard_B2ms"
        diskType = "Standard_LRS"
        pypi = [ordered]@{
            tier2 = [ordered]@{ diskSize = 8191 }
            tier3 = [ordered]@{ diskSize = 511 }
        }
        cran = [ordered]@{
            tier2 = [ordered]@{ diskSize = 127 }
            tier3 = [ordered]@{ diskSize = 31 }
        }
    }
    # Set password secret name and IP address for each mirror
    foreach ($tier in @(2, 3)) {
        foreach ($direction in @("internal", "external")) {
            # Please note that each mirror type must have a distinct ipOffset in the range 4-15
            foreach ($typeOffset in @(("pypi", 4), ("cran", 5))) {
                $shm.mirrors[$typeOffset[0]]["tier${tier}"][$direction] = [ordered]@{
                    adminPasswordSecretName = "shm-$($shm.id)-vm-admin-password-$($typeOffset[0])-${direction}-mirror-tier-${tier}".ToLower()
                    ipAddress = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.mirrorVnets["tier${tier}"].subnets[$direction].cidr -Offset $typeOffset[1]
                    vmName = "$($typeOffset[0])-${direction}-MIRROR-TIER-${tier}".ToUpper()
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
Export-ModuleMember -Function Get-ShmFullConfig


# Get SRE configuration
# ---------------------
function Get-SreConfig {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
        [string]$configId
    )
    # Read full SRE config from file
    return Get-ConfigFile -configType "sre" -configLevel "full" -configName $configId
}
Export-ModuleMember -Function Get-SreConfig
