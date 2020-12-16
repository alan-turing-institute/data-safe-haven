Import-Module Az.RecoveryServices -ErrorAction Stop # Note that this contains TimeZoneConverter
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop
Import-Module $PSScriptRoot/Networking -ErrorAction Stop
Import-Module $PSScriptRoot/Security -ErrorAction Stop


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
    # Set default Nexus usage
    $nexusDefault = ($sreConfigBase.tier -eq "2") ? $true : $false
    $config = [ordered]@{
        shm = Get-ShmFullConfig -shmId $sreConfigBase.shmId
        sre = [ordered]@{
            id               = $sreConfigBase.sreId | Limit-StringLength -MaximumLength 7 -FailureIsFatal
            rgPrefix         = $sreConfigBase.overrides.sre.rgPrefix ? $sreConfigBase.overrides.sre.rgPrefix : "RG_SHM_$($sreConfigBase.shmId)_SRE_$($sreConfigBase.sreId)".ToUpper()
            nsgPrefix        = $sreConfigBase.overrides.sre.nsgPrefix ? $sreConfigBase.overrides.sre.nsgPrefix : "NSG_SHM_$($sreConfigBase.shmId)_SRE_$($sreConfigBase.sreId)".ToUpper()
            shortName        = "sre-$($sreConfigBase.sreId)".ToLower()
            subscriptionName = $sreConfigBase.subscriptionName
            tier             = $sreConfigBase.tier
            nexus            = $sreConfigBase.nexus -is [bool] ? $sreConfigBase.nexus : $nexusDefault
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
    $sreDomain = $sreConfigBase.domain ? $sreConfigBase.domain : "$($config.sre.id).$($config.shm.domain.fqdn)"
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
                deployment = [ordered]@{
                    name = "DeploymentSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet).0/24"
                    nsg  = [ordered]@{
                        name  = "$($config.sre.nsgPrefix)_DEPLOYMENT".ToUpper()
                        rules = "sre-nsg-rules-compute-deployment.json"
                    }
                }
                rds        = [ordered]@{
                    name = "RDSSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 1).0/24"
                }
                data       = [ordered]@{
                    name = "PrivateDataSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 2).0/24"
                }
                databases  = [ordered]@{
                    name = "DatabasesSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 3).0/24"
                    nsg  = [ordered]@{
                        name  = "$($config.sre.nsgPrefix)_DATABASES".ToUpper()
                        rules = "sre-nsg-rules-databases.json"
                    }
                }
                compute    = [ordered]@{
                    name = "ComputeSubnet"
                    cidr = "${sreBasePrefix}.$([int]$sreThirdOctet + 4).0/24"
                    nsg  = [ordered]@{
                        name  = "$($config.sre.nsgPrefix)_COMPUTE".ToUpper()
                        rules = "sre-nsg-rules-compute.json"
                    }
                }
                webapps    = [ordered]@{
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
    $storageRg = "$($config.sre.rgPrefix)_ARTIFACTS".ToUpper()
    $sreStoragePrefix = "$($config.shm.id)$($config.sre.id)"
    $sreStorageSuffix = New-RandomLetters -SeedPhrase "$($config.sre.subscriptionName)$($config.sre.id)"
    # Storage configuration entries
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
            accountName = "${sreStoragePrefix}artifacts${sreStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
            rg          = $storageRg
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
                accessTier  = "hot"
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
                storageKind        = ($config.sre.tier -eq "1") ? "FileStorage" : "BlobStorage"
                performance        = ($config.sre.tier -eq "1") ? "Premium_LRS" : "Standard_LRS" # see https://docs.microsoft.com/en-us/azure/storage/common/storage-account-overview#types-of-storage-accounts for allowed types
                accessTier         = "hot"
                allowedIpAddresses = $sreConfigBase.dataAdminIpAddresses ? @($sreConfigBase.dataAdminIpAddresses) : $shm.dsvmImage.build.nsg.allowedIpAddresses
            }
            containers = [ordered]@{
                ingress = [ordered]@{
                    accessPolicyName = "readOnly"
                    mountType        = ($config.sre.tier -eq "1") ? "ShareSMB" : "BlobSMB"
                }
                egress  = [ordered]@{
                    accessPolicyName = "readWrite"
                    mountType        = ($config.sre.tier -eq "1") ? "ShareSMB" : "BlobSMB"
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

    # RDS Servers
    # -----------
    $config.sre.rds = [ordered]@{
        rg             = "$($config.sre.rgPrefix)_RDS".ToUpper()
        gateway        = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-rds-gateway"
            vmName                  = "RDG-SRE-$($config.sre.id)".ToUpper() | Limit-StringLength -MaximumLength 15
            vmSize                  = "Standard_DS2_v2"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.rds.cidr -Offset 4
            nsg                     = [ordered]@{
                name  = "$($config.sre.nsgPrefix)_RDS_SERVER".ToUpper()
                rules = "sre-nsg-rules-gateway.json"
            }
            networkRules            = [ordered]@{}
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
        appSessionHost = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-rds-sh1"
            vmName                  = "APP-SRE-$($config.sre.id)".ToUpper() | Limit-StringLength -MaximumLength 15
            vmSize                  = "Standard_DS2_v2"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.rds.cidr -Offset 5
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


    # HackMD and Gitlab servers
    # -------------------------
    $config.sre.webapps = [ordered]@{
        rg     = "$($config.sre.rgPrefix)_WEBAPPS".ToUpper()
        gitlab = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-gitlab"
            vmName                  = "GITLAB-SRE-$($config.sre.id)".ToUpper()
            vmSize                  = "Standard_D2s_v3"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.webapps.cidr -Offset 5
            rootPasswordSecretName  = "$($config.sre.shortName)-other-gitlab-root-password"
            osVersion               = "18.04-LTS"
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
        hackmd = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-hackmd"
            vmName                  = "HACKMD-SRE-$($config.sre.id)".ToUpper()
            vmSize                  = "Standard_D2s_v3"
            ip                      = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.webapps.cidr -Offset 6
            osVersion               = "18.04-LTS"
            codimd                  = [ordered]@{
                dockerVersion = "2.2.0"
            }
            postgres                = [ordered]@{
                passwordSecretName = "$($config.sre.shortName)-other-hackmd-password-postgresdb"
                dockerVersion      = "13.1"
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
        MSSQL      = @{port = "1433"; prefix = "MSSQL"; sku = "sqldev" }
        PostgreSQL = @{port = "5432"; prefix = "PSTGRS"; sku = "18.04-LTS" }
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

    # Compute VMs
    # -----------
    $config.sre.dsvm = [ordered]@{
        adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-compute"
        rg                      = "$($config.sre.rgPrefix)_COMPUTE".ToUpper()
        vmImage                 = [ordered]@{
            subscription = $config.shm.dsvmImage.subscription
            rg           = $config.shm.dsvmImage.gallery.rg
            gallery      = $config.shm.dsvmImage.gallery.sig
            type         = $sreConfigBase.computeVmImage.type
            version      = $sreConfigBase.computeVmImage.version
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
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SHM ID")]
        $shmId
    )
    # Import minimal management config parameters from JSON config file - we can derive the rest from these
    $shmConfigBase = Get-ConfigFile -configType "shm" -configLevel "core" -configName $shmId
    $shmIpPrefix = "10.0.0"  # This does not need to be user-configurable. Different SHMs can share the same address space as they are never peered.

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
    }

    # Set timezone and NTP configuration
    # NB. Very few NTP services provide an exhaustive, stable list of IP addresses. The Google NTP servers are incompatible with others due to leap-second smearing
    # -------------------------------------------------------------------------------------------------------------------------------------------------------------
    $timezoneLinux = $shmConfigBase.timezone ? $shmConfigBase.timezone : "Europe/London"
    $shm.time = [ordered]@{
        timezone = [ordered]@{
            linux   = $timezoneLinux
            windows = [TimeZoneConverter.TZConvert]::IanaToWindows($timezoneLinux)
        }
        ntp      = [ordered]@{
            poolFqdn        = "time.google.com"
            serverAddresses = @("216.239.35.0", "216.239.35.4", "216.239.35.8", "216.239.35.12")
            serverFqdns     = @("time.google.com", "time1.google.com", "time2.google.com", "time3.google.com", "time4.google.com")
        }
    }

    # DSVM build images
    # -----------------
    # Since an ImageGallery cannot be moved once created, we must ensure that the location parameter matches any gallery that already exists
    $originalContext = Get-AzContext
    $vmImagesSubscriptionName = $shmConfigBase.vmImages.subscriptionName ? $shmConfigBase.vmImages.subscriptionName : $shm.subscriptionName
    $vmImagesLocation = $shmConfigBase.vmImages.location ? $shmConfigBase.vmImages.location : $shm.location
    $null = Set-AzContext -SubscriptionId $vmImagesSubscriptionName -ErrorAction Stop
    $locations = Get-AzResource | Where-Object { $_.ResourceGroupName -like "RG_SH_*" } | ForEach-Object { $_.Location } | Sort-Object | Get-Unique
    if ($locations.Count -gt 1) {
        Add-LogMessage -Level Fatal "Image building resources found in multiple locations: ${locations}!"
    } elseif ($locations.Count -eq 1) {
        if ($vmImagesLocation -ne $locations) {
            Add-LogMessage -Level Fatal "Image building location ($vmImagesLocation) must be set to ${locations}!"
        }
    }
    $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    # Construct build images config
    $dsvmImageStorageSuffix = New-RandomLetters -SeedPhrase $vmImagesSubscriptionName
    $shm.dsvmImage = [ordered]@{
        subscription    = $vmImagesSubscriptionName
        location        = $vmImagesLocation
        bootdiagnostics = [ordered]@{
            rg          = "RG_SH_BOOT_DIAGNOSTICS"
            accountName = "buildimgbootdiags${dsvmImageStorageSuffix}".ToLower() | Limit-StringLength -MaximumLength 24 -Silent
        }
        build           = [ordered]@{
            rg     = "RG_SH_BUILD_CANDIDATES"
            nsg    = [ordered]@{
                name               = "NSG_IMAGE_BUILD"
                allowedIpAddresses = $shmConfigbase.vmImages.buildIpAddresses ? @($shmConfigbase.vmImages.buildIpAddresses) : @(193.60.220.240, 193.60.220.253)
            }
            vnet   = [ordered]@{
                name = "VNET_IMAGE_BUILD"
                cidr = "10.48.0.0/16"
            }
            subnet = [ordered]@{
                name = "ImageBuildSubnet"
                cidr = "10.48.0.0/24"
            }
            # Only the R-package installation is parallelisable and 8 GB of RAM is sufficient
            # We want a compute-optimised VM, since per-core performance is the bottleneck
            vm     = [ordered]@{
                diskSizeGb = 64
                size       = "Standard_F4s_v2"
            }
        }
        gallery         = [ordered]@{
            rg                = "RG_SH_IMAGE_GALLERY"
            sig               = "SAFE_HAVEN_COMPUTE_IMAGES"
            imageMajorVersion = 0
            imageMinorVersion = 3
        }
        images          = [ordered]@{
            rg = "RG_SH_IMAGE_STORAGE"
        }
        keyVault        = [ordered]@{
            rg   = "RG_SH_SECRETS"
            name = "kv-shm-$($shm.id)-dsvm-imgs".ToLower() | Limit-StringLength -MaximumLength 24
        }
        network         = [ordered]@{
            rg = "RG_SH_NETWORKING"
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

    # Logging config
    # --------------
    $shm.logging = [ordered]@{
        rg            = "$($shm.rgPrefix)_LOGGING".ToUpper()
        workspaceName = "shm$($shm.id)loganalytics${storageSuffix}".ToLower()
    }

    # Network config
    # --------------
    # Deconstruct base address prefix to allow easy construction of IP based parameters
    $shmPrefixOctets = $shmIpPrefix.Split(".")
    $shmBasePrefix = "$($shmPrefixOctets[0]).$($shmPrefixOctets[1])"
    $shmThirdOctet = ([int]$shmPrefixOctets[2])
    $shm.network = [ordered]@{
        vnet           = [ordered]@{
            rg      = "$($shm.rgPrefix)_NETWORKING".ToUpper()
            name    = "VNET_SHM_$($shm.id)".ToUpper()
            cidr    = "${shmBasePrefix}.${shmThirdOctet}.0/21"
            subnets = [ordered]@{
                identity = [ordered]@{
                    name = "IdentitySubnet"
                    cidr = "${shmBasePrefix}.${shmThirdOctet}.0/24"
                    nsg  = [ordered]@{
                        name = "$($shm.nsgPrefix)_IDENTITY".ToUpper()
                    }
                }
                firewall = [ordered]@{
                    # NB. The firewall subnet MUST be named 'AzureFirewallSubnet'. See https://docs.microsoft.com/en-us/azure/firewall/tutorial-firewall-deploy-portal
                    name = "AzureFirewallSubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 2).0/24"
                }
                gateway  = [ordered]@{
                    # NB. The Gateway subnet MUST be named 'GatewaySubnet'. See https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq#do-i-need-a-gatewaysubnet
                    name = "GatewaySubnet"
                    cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 7).0/24"
                }
            }
        }
        vpn            = [ordered]@{
            cidr = "172.16.201.0/24" # NB. this must not overlap with the VNet that the VPN gateway is part of
        }
        repositoryVnet = [ordered]@{
            name    = "VNET_SHM_$($shm.id)_NEXUS_REPOSITORY_TIER_2".ToUpper()
            cidr    = "10.30.1.0/24"
            subnets = [ordered]@{
                repository = [ordered]@{
                    name = "RepositorySubnet"
                    cidr = "10.30.1.0/24"
                    nsg  = [ordered]@{
                        name  = "$($shm.nsgPrefix)_NEXUS_REPOSITORY_TIER_2".ToUpper()
                        rules = "shm-nsg-rules-nexus.json"
                    }
                }
            }
        }
        mirrorVnets    = [ordered]@{}
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
                        name = "$($shm.nsgPrefix)_EXTERNAL_PACKAGE_MIRRORS_TIER${tier}".ToUpper()
                    }
                }
                internal = [ordered]@{
                    name = "InternalPackageMirrorsTier${tier}Subnet"
                    cidr = "${shmMirrorPrefix}.16/28"
                    nsg  = [ordered]@{
                        name = "$($shm.nsgPrefix)_INTERNAL_PACKAGE_MIRRORS_TIER${tier}".ToUpper()
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
        fqdn                       = "${hostname}.$($shm.domain.fqdn)"
        ip                         = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.vnet.subnets.identity.cidr -Offset 4
        external_dns_resolver      = "168.63.129.16"  # https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
        safemodePasswordSecretName = "shm-$($shm.id)-vm-safemode-password-dc".ToLower()
        disks                      = [ordered]@{
            data = [ordered]@{
                sizeGb = "20"
                type   = "Standard_LRS"
            }
            os   = [ordered]@{
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
        vmSize   = "Standard_D2s_v3"
        hostname = $hostname
        fqdn     = "${hostname}.$($shm.domain.fqdn)"
        ip       = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.vnet.subnets.identity.cidr -Offset 5
        disks    = [ordered]@{
            data = [ordered]@{
                sizeGb = "20"
                type   = "Standard_LRS"
            }
            os   = [ordered]@{
                sizeGb = "128"
                type   = "Standard_LRS"
            }
        }
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
        disks                   = [ordered]@{
            data = [ordered]@{
                sizeGb = "20"
                type   = "Standard_LRS"
            }
            os   = [ordered]@{
                sizeGb = "128"
                type   = "Standard_LRS"
            }
        }
    }

    # Storage config
    # --------------
    $shmStoragePrefix = "shm$($shm.id)"
    $shmStorageSuffix = New-RandomLetters -SeedPhrase "$($shm.subscriptionName)$($shm.id)"
    $storageRg = "$($shm.rgPrefix)_ARTIFACTS".ToUpper()
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
    # --------------------------
    $shm.repository = [ordered]@{
        rg       = "$($shm.rgPrefix)_NEXUS_REPOSITORIES".ToUpper()
        vmSize   = "Standard_B2ms"
        diskType = "Standard_LRS"
        nexus    = [ordered]@{
            adminPasswordSecretName         = "shm-$($shm.id)-vm-admin-password-nexus".ToLower()
            nexusAppAdminPasswordSecretName = "shm-$($shm.id)-nexus-repository-admin-password".ToLower()
            ipAddress                       = "10.30.1.10"
            vmName                          = "NEXUS-REPOSITORY-TIER-2"
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
            tier3 = [ordered]@{ diskSize = 512 }
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
