Import-Module $PSScriptRoot/Logging.psm1
Import-Module $PSScriptRoot/Networking.psm1
Import-Module $PSScriptRoot/Security.psm1


# Get root directory for configuration files
# ------------------------------------------
function Copy-HashtableOverrides {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Source hashtable")]
        $Source,
        [Parameter(Mandatory = $true, HelpMessage = "Target hashtable to override")]
        $Target
    )
    foreach ($sourcePair in $Source.GetEnumerator()) {
        # If we hit a leaf then override the target with the source value
        if ($sourcePair.Value -isnot [Hashtable]) {
            $target[$sourcePair.Key] = $sourcePair.Value
            continue
        }
        # If this key is not in the target then we add it
        if (-not $Target.Contains($sourcePair.Key)) {
            $target[$sourcePair.Key] = $sourcePair.Value
            continue
        }
        Copy-HashtableOverrides $sourcePair.Value $Target[$sourcePair.Key]
    }
}
Export-ModuleMember -Function Copy-HashtableOverrides


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
    $shmIpPrefix = "10.0.0"  # this does not need to be user-configurable as it is never changed in practice

    # Safe Haven management config
    # ----------------------------
    $shm = [ordered]@{
        subscriptionName = $shmConfigBase.subscriptionName
        id = $shmConfigBase.shmId
        name = $shmConfigBase.name
        organisation = $shmConfigBase.organisation
        location = $shmConfigBase.location
        adminSecurityGroupName = $shmConfigBase.adminSecurityGroupName
    }

    # DSVM build images
    # -----------------
    $shm.dsvmImage = [ordered]@{
        subscription = $shmConfigBase.computeVmImageSubscriptionName
        # In principle this should be kept in-sync with $shm.location but as an ImageGallery cannot be moved once created, we hard-code it here
        location = "uksouth"
        bootdiagnostics = [ordered]@{
            rg = "RG_SH_BOOT_DIAGNOSTICS"
            accountName = "build$($shm.id)bootdiags${storageSuffix}".ToLower() | Limit-StringLength 24
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
            # Only the R-package installation is parallelisable
            # => per-core performance is the bottleneck
            # 8 GB of RAM is sufficient so we want a compute-optimised VM
            vmSize = "Standard_F4s_v2"
        }
        gallery = [ordered]@{
            rg = "RG_SH_IMAGE_GALLERY"
            sig = "SAFE_HAVEN_COMPUTE_IMAGES"
            imageMajorVersion = 0
            imageMinorVersion = 2
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
    $shmDomainDN = "DC=$(($shmConfigBase.domain).Replace('.',',DC='))"
    $shm.domain = [ordered]@{
        fqdn = $shmConfigBase.domain
        netbiosName = ($shmConfigBase.netbiosName ? $shmConfigBase.netbiosName : $shm.id).ToUpper() | Limit-StringLength 15 -FailureIsFatal
        dn = $shmDomainDN
        serviceServerOuPath = "OU=Safe Haven Service Servers,${shmDomainDN}"
        serviceOuPath = "OU=Safe Haven Service Accounts,${shmDomainDN}"
        userOuPath = "OU=Safe Haven Research Users,${shmDomainDN}"
        securityOuPath = "OU=Safe Haven Security Groups,${shmDomainDN}"
    }
    $shm.domain.securityGroups = [ordered]@{
        computerManagers = [ordered]@{ name = "SG Safe Haven Computer Management Users" }
        serverAdmins = [ordered]@{ name = "SG Safe Haven Server Administrators" }
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
            rg = "RG_SHM_$($shm.id)_NETWORKING".ToUpper()
            name = "VNET_SHM_$($shm.id)".ToUpper()
            cidr = "${shmBasePrefix}.${shmThirdOctet}.0/21"
        }
        subnets = [ordered]@{
            identity = [ordered]@{
                name = "IdentitySubnet"
                cidr = "${shmBasePrefix}.${shmThirdOctet}.0/24"
            }
            web = [ordered]@{
                name = "WebSubnet"
                cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 1).0/24"
            }
            gateway = [ordered]@{
                # NB. The Gateway subnet MUST be named 'GatewaySubnet'. See https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq#do-i-need-a-gatewaysubnet
                name = "GatewaySubnet"
                cidr = "${shmBasePrefix}.$([int]$shmThirdOctet + 7).0/24"
            }
        }
    }

    # Domain controller config
    # ------------------------
    $hostname = "DC1-SHM-$($shm.id)".ToUpper() | Limit-StringLength 15
    $shm.dc = [ordered]@{
        rg = "RG_SHM_$($shm.id)_DC".ToUpper()
        vmName = $hostname
        vmSize = "Standard_D2s_v3"
        hostname = $hostname
        fqdn = "${hostname}.$($shm.domain.fqdn)"
        ip = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.subnets.identity.cidr -Offset 4
        external_dns_resolver = "168.63.129.16"  # https://docs.microsoft.com/en-us/azure/virtual-network/what-is-ip-address-168-63-129-16
    }

    # Backup domain controller config
    # -------------------------------
    $hostname = "DC2-SHM-$($shm.id)".ToUpper() | Limit-StringLength 15
    $shm.dcb = [ordered]@{
        vmName = $hostname
        hostname = $hostname
        fqdn = "${hostname}.$($shm.domain.fqdn)"
        ip = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.subnets.identity.cidr -Offset 5
    }

    # NPS config
    # ----------
    $hostname = "NPS-SHM-$($shm.id)".ToUpper() | Limit-StringLength 15
    $shm.nps = [ordered]@{
        rg = "RG_SHM_$($shm.id)_NPS".ToUpper()
        vmName = $hostname
        vmSize = "Standard_D2s_v3"
        hostname = $hostname
        ip = Get-NextAvailableIpInRange -IpRangeCidr $shm.network.subnets.identity.cidr -Offset 6
    }

    # Storage config
    # --------------
    $storageSuffix = New-RandomLetters -SeedPhrase ($shm.subscriptionName + $shm.id)
    $storageRg = "RG_SHM_$($shm.id)_ARTIFACTS".ToUpper()
    $shm.storage = [ordered]@{
        artifacts = [ordered]@{
            rg = $storageRg
            accountName = "shm$($shm.id)artifacts${storageSuffix}".ToLower() | Limit-StringLength 24 -Silent
        }
        bootdiagnostics = [ordered]@{
            rg = $storageRg
            accountName = "shm$($shm.id)bootdiags${storageSuffix}".ToLower() | Limit-StringLength 24 -Silent
        }
    }

    # Secrets config
    # --------------
    $shm.keyVault = [ordered]@{
        rg = "RG_SHM_$($shm.id)_SECRETS".ToUpper()
        name = "kv-shm-$($shm.id)".ToLower() | Limit-StringLength 24
        secretNames = [ordered]@{
            aadAdminPassword = "shm-$($shm.id)-aad-admin-password".ToLower()
            buildImageAdminUsername = "shm-$($shm.id)-buildimage-admin-username".ToLower()
            buildImageAdminPassword = "shm-$($shm.id)-buildimage-admin-password".ToLower()
            dcSafemodePassword = "shm-$($shm.id)-vm-safemode-password-dc".ToLower()
            domainAdminPassword = "shm-$($shm.id)-domain-admin-password".ToLower()
            localAdsyncPassword = "shm-$($shm.id)-localadsync-password".ToLower()
            npsAdminPassword = "shm-$($shm.id)-vm-admin-password-nps".ToLower()
            vmAdminUsername = "shm-$($shm.id)-domain-admin-username".ToLower()
            vpnCaCertificate = "shm-$($shm.id)-vpn-ca-cert".ToLower()
            vpnCaCertificatePlain = "shm-$($shm.id)-vpn-ca-cert-plain".ToLower()
            vpnCaCertPassword = "shm-$($shm.id)-vpn-ca-cert-password".ToLower()
            vpnClientCertificate = "shm-$($shm.id)-vpn-client-cert".ToLower()
            vpnClientCertPassword = "shm-$($shm.id)-vpn-client-cert-password".ToLower()
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
    # Please note that each mirror type must have a distinct ipOffset in the range 4-15
    $shm.mirrors = [ordered]@{
        rg = "RG_SHM_$($shm.id)_PKG_MIRRORS".ToUpper()
        vmSize = "Standard_B2ms"
        diskType = "Standard_LRS"
        pypi = [ordered]@{
            ipOffset = 4
            diskSize = [ordered]@{
                tier2 = 8191
                tier3 = 511
            }
        }
        cran = [ordered]@{
            ipOffset = 5
            diskSize = [ordered]@{
                tier2 = 127
                tier3 = 31
            }
        }
    }

    # Apply overrides (if any exist)
    # ------------------------------
    if ($shmConfigBase.overrides) {
        Copy-HashtableOverrides -Source $shmConfigBase.overrides -Target $shm
    }

    return $shm
}
Export-ModuleMember -Function Get-ShmFullConfig


function Limit-StringLength {
    param(
        [Parameter(Mandatory = $True, ValueFromPipeline = $True)]
        [string]$InputString,
        [Parameter(Position = 0, Mandatory = $True)]
        [int]$MaximumLength,
        [Parameter(Mandatory=$false)]
        [Switch]$FailureIsFatal,
        [Parameter(Mandatory=$false)]
        [Switch]$Silent
    )
    if ($InputString.Length -le $MaximumLength) {
        return $InputString
    }
    if ($FailureIsFatal) {
        Add-LogMessage -Level Fatal "'$InputString' has length $($InputString.Length) but must not exceed $MaximumLength!"
    }
    if (-Not $Silent) {
        Add-LogMessage -Level Warning "Truncating '$InputString' to length $MaximumLength!"
    }
    return $InputString[0..($MaximumLength - 1)] -join ""
}
Export-ModuleMember -Function Limit-StringLength


# Add a new SRE configuration
# ---------------------------
function Add-SreConfig {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
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
            subscriptionName = $sreConfigBase.subscriptionName
            id = $sreConfigBase.sreId | Limit-StringLength 7 -FailureIsFatal
            shortName = "sre-$($sreConfigBase.sreId)".ToLower()
            tier = $sreConfigBase.tier
            adminSecurityGroupName = $sreConfigBase.adminSecurityGroupName
        }
    }
    $config.sre.location = $config.shm.location

    # Domain config
    # -------------
    $config.sre.domain = [ordered]@{
        fqdn = $sreConfigBase.domain
        netbiosName = $($config.sre.id).ToUpper() | Limit-StringLength 15 -FailureIsFatal
        dn = "DC=$($sreConfigBase.domain.Replace('.',',DC='))"
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
            rg = "RG_SRE_$($config.sre.id)_NETWORKING".ToUpper()
            name = "VNET_SRE_$($config.sre.id)".ToUpper()
            cidr = "${sreBasePrefix}.${sreThirdOctet}.0/21"
        }
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
        nsg = [ordered]@{
            data = [ordered]@{}
            databases = [ordered]@{
                name = "NSG_SRE_$($config.sre.id)_DATABASES".ToUpper()
            }
        }
    }

    # Storage config
    # --------------
    $storageRg = "RG_SRE_$($config.sre.id)_ARTIFACTS".ToUpper()
    $storageSuffix = New-RandomLetters -SeedPhrase ($config.sre.subscriptionName + $config.sre.id)
    $config.sre.storage = [ordered]@{
        artifacts = [ordered]@{
            rg = $storageRg
            accountName = "sre$($config.sre.id)artifacts${storageSuffix}".ToLower() | Limit-StringLength 24 -Silent
        }
        bootdiagnostics = [ordered]@{
            rg = $storageRg
            accountName = "sre$($config.sre.id)bootdiags${storageSuffix}".ToLower() | Limit-StringLength 24 -Silent
        }
    }

    # Secrets config
    # --------------
    $config.sre.keyVault = [ordered]@{
        name = "kv-$($config.shm.id)-sre-$($config.sre.id)".ToLower() | Limit-StringLength 24
        rg = "RG_SRE_$($config.sre.id)_SECRETS".ToUpper()
        secretNames = [ordered]@{
            adminUsername = "$($config.sre.shortName)-vm-admin-username"
            dsvmAdminPassword = "$($config.sre.shortName)-vm-admin-password-compute"
            gitlabRootPassword = "$($config.sre.shortName)-other-gitlab-root-password"
            gitlabUserPassword = "$($config.sre.shortName)-other-gitlab-user-password"
            hackmdUserPassword = "$($config.sre.shortName)-other-hackmd-user-password"
            letsEncryptCertificate = "$($config.sre.shortName)-lets-encrypt-certificate"
            npsSecret = "$($config.sre.shortName)-other-nps-secret"
            postgresDbAdminUsername = "$($config.sre.shortName)-db-admin-username-postgres"
            postgresDbAdminPassword = "$($config.sre.shortName)-db-admin-password-postgres"
            postgresVmAdminPassword = "$($config.sre.shortName)-vm-admin-password-postgres"
            sqlAuthUpdateUsername = "$($config.sre.shortName)-db-admin-username-mssql"
            sqlAuthUpdateUserPassword = "$($config.sre.shortName)-db-admin-password-mssql"
            sqlVmAdminPassword = "$($config.sre.shortName)-vm-admin-password-mssql"
            webappAdminPassword = "$($config.sre.shortName)-vm-admin-password-webapp"
        }
    }

    # --- Domain users ---
    $config.sre.users = [ordered]@{
        computerManagers = [ordered]@{
            gitlab = [ordered]@{
                name = "$($config.sre.domain.netbiosName) Gitlab VM Service Account"
                samAccountName = "$($config.sre.id)vmgitlab".ToLower() | Limit-StringLength 20
                passwordSecretName = "$($config.sre.shortName)-vm-service-account-password-gitlab"
            }
            hackmd = [ordered]@{
                name = "$($config.sre.domain.netbiosName) HackMD VM Service Account"
                samAccountName = "$($config.sre.id)vmhackmd".ToLower() | Limit-StringLength 20
                passwordSecretName = "$($config.sre.shortName)-vm-service-account-password-hackmd"
            }
            dsvm = [ordered]@{
                name = "$($config.sre.domain.netbiosName) Compute VM Service Account"
                samAccountName = "$($config.sre.id)vmcompute".ToLower() | Limit-StringLength 20
                passwordSecretName = "$($config.sre.shortName)-vm-service-account-password-compute"
            }
            postgres = [ordered]@{
                name = "$($config.sre.domain.netbiosName) Postgres VM Service Account"
                samAccountName = "$($config.sre.id)vmpostgres".ToLower() | Limit-StringLength 20
                passwordSecretName = "$($config.sre.shortName)-vm-service-account-password-postgres"
            }
        }
        serviceAccounts = [ordered]@{
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
        rg = "RG_SRE_$($config.sre.id)_RDS".ToUpper()
        gateway = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-rds"
            vmName = "RDG-SRE-$($config.sre.id)".ToUpper() | Limit-StringLength 15
            vmSize = "Standard_DS2_v2"
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.subnets.rds.cidr -Offset 4
            nsg = "NSG_SRE_$($config.sre.id)_RDS_SERVER".ToUpper()
            networkRules = [ordered]@{}
        }
        sessionHost1 = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-rds"
            vmName = "APP-SRE-$($config.sre.id)".ToUpper() | Limit-StringLength 15
            vmSize = "Standard_DS2_v2"
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.subnets.rds.cidr -Offset 5
            nsg = "NSG_SRE_$($config.sre.id)_RDS_SESSION_HOSTS".ToUpper()
        }
        sessionHost2 = [ordered]@{
            adminPasswordSecretName = "$($config.sre.shortName)-vm-admin-password-rds"
            vmName = "DKP-SRE-$($config.sre.id)".ToUpper() | Limit-StringLength 15
            vmSize = "Standard_DS2_v2"
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.subnets.rds.cidr -Offset 6
            nsg = "NSG_SRE_$($config.sre.id)_RDS_SESSION_HOSTS".ToUpper()
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
        rg = "RG_SRE_$($config.sre.id)_DATA".ToUpper()
        nsg = "NSG_SRE_$($config.sre.id)_DATA".ToUpper()
        vmName = $hostname
        vmSize = "Standard_D2s_v3"
        hostname = $hostname
        fqdn = "${hostname}.$($config.shm.domain.fqdn)"
        ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.subnets.data.cidr -Offset 4
        egressDiskGb = 512
        ingressDiskGb = 512
        sharedDiskGb = 512
    }

    # HackMD and Gitlab servers
    # -------------------------
    $config.sre.webapps = [ordered]@{
        rg = "RG_SRE_$($config.sre.id)_WEBAPPS".ToUpper()
        nsg = "NSG_SRE_$($config.sre.id)_WEBAPPS".ToUpper()
        gitlab = [ordered]@{
            vmName = "GITLAB-SRE-$($config.sre.id)".ToUpper()
            vmSize = "Standard_D2s_v3"
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.subnets.data.cidr -Offset 5

        }
        hackmd = [ordered]@{
            vmName = "HACKMD-SRE-$($config.sre.id)".ToUpper()
            vmSize = "Standard_D2s_v3"
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.subnets.data.cidr -Offset 6

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
        rg = "RG_SRE_$($config.sre.id)_DATABASES".ToUpper()
    }
    $ipOffset = 4
    $dbPorts = @{"MSSQL" = "14330"; "PostgreSQL" = "5432"}
    $dbSkus = @{"MSSQL" = "sqldev"; "PostgreSQL" = "18.04-LTS"}
    $dbHostnamePrefix = @{"MSSQL" = "MSSQL"; "PostgreSQL" = "PSTGRS"}
    foreach ($databaseType in $sreConfigBase.databases) {
        $config.sre.databases["db$($databaseType.ToLower())"]  = [ordered]@{
            vmName = "$($dbHostnamePrefix[$databaseType])-$($config.sre.id)".ToUpper() | Limit-StringLength 15
            type = $databaseType
            ip = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.subnets.databases.cidr -Offset $ipOffset
            port = $dbPorts[$databaseType]
            sku = $dbSkus[$databaseType]
            subnet = "databases"
            vmSize = "Standard_DS2_v2"
            datadisk = [ordered]@{
                size_gb = "1024"
                type = "Standard_LRS"
            }
            osdisk = [ordered]@{
                size_gb = "128"
                type = "Standard_LRS"
            }
        }
        if ($databaseType -eq "MSSQL") { $config.sre.databases["db$($databaseType.ToLower())"]["enableSSIS"] = $true }
        $ipOffset += 1
    }

    # Compute VMs
    # -----------
    $config.sre.dsvm = [ordered]@{
        rg = "RG_SRE_$($config.sre.id)_COMPUTE".ToUpper()
        nsg = "NSG_SRE_$($config.sre.Id)_COMPUTE".ToUpper()
        deploymentNsg = "NSG_SRE_$($config.sre.Id)_COMPUTE_DEPLOYMENT".ToUpper()
        vmImageSubscription = $config.shm.dsvmImage.subscription
        vmImageResourceGroup = $config.shm.dsvmImage.gallery.rg
        vmImageGallery = $config.shm.dsvmImage.gallery.sig
        vmSizeDefault = "Standard_D2s_v3"
        vmImageType = $sreConfigBase.computeVmImageType
        vmImageVersion = $sreConfigBase.computeVmImageVersion
        osdisk = [ordered]@{
            type = "Standard_LRS"
            size_gb = "64"
        }
        scratchdisk = [ordered]@{
            type = "Standard_LRS"
            size_gb = "512"
        }
        homedisk = [ordered]@{
            type = "Standard_LRS"
            size_gb = "128"
        }
    }
    $config.shm.Remove("dsvmImage")

    # Package mirror config
    # ---------------------
    $config.sre.mirrors = [ordered]@{
        vnet = [ordered]@{}
        cran = [ordered]@{}
        pypi = [ordered]@{}
    }
    # Tier-2 and Tier-3 mirrors use different IP ranges for their VNets so they can be easily identified
    if (@("2", "3").Contains($config.sre.tier)) {
        $config.sre.mirrors.vnet.name = "VNET_SHM_$($config.shm.id)_PACKAGE_MIRRORS_TIER$($config.sre.tier)".ToUpper()
        $config.sre.mirrors.pypi.ip = "10.20.$($config.sre.tier).20"
        $config.sre.mirrors.cran.ip = "10.20.$($config.sre.tier).21"
    } elseif (@("0", "1").Contains($config.sre.tier)) {
        $config.sre.mirrors.vnet.name = $null
        $config.sre.mirrors.pypi.ip = $null
        $config.sre.mirrors.cran.ip = $null
    } else {
        Write-Error "Tier '$($config.sre.tier)' not supported (NOTE: Tier must be provided as a string in the core SRE config.)"
        return
    }

    # Apply overrides (if any exist)
    # ------------------------------
    if ($sreConfigBase.overrides) {
        Copy-HashtableOverrides -Source $sreConfigBase.overrides -Target $config
    }

    # Write output to file
    # --------------------
    $jsonOut = ($config | ConvertTo-Json -Depth 10)
    $sreFullConfigPath = Join-Path $(Get-ConfigRootDir) "full" "sre_${configId}_full_config.json"
    Out-File -FilePath $sreFullConfigPath -Encoding "UTF8" -InputObject $jsonOut
    Add-LogMessage -Level Info "Wrote config file to '$sreFullConfigPath'"
}
Export-ModuleMember -Function Add-SreConfig


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
