# Get root directory for configuration files
# ------------------------------------------
function Get-ConfigRootDir{
    $configRootDir = Join-Path (Get-Item $PSScriptRoot).Parent "environment_configs" -Resolve
    return $configRootDir
}

# Get SHM configuration
# ---------------------
function Get-ShmFullConfig{
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID ('test' or 'prod')")]
        $shmId
    )
    $configRootDir = Get-ConfigRootDir
    $shmCoreConfigFilename = "shm_" + $shmId + "_core_config.json"
    $shmCoreConfigPath = Join-Path $configRootDir "core" $shmCoreConfigFilename -Resolve

    # Import minimal management config parameters from JSON config file - we can derive the rest from these
    $shmConfigBase = Get-Content -Path $shmCoreConfigPath -Raw | ConvertFrom-Json


    # === SH MANAGEMENT CONFIG ===
    $shm = [ordered]@{}
    $shmPrefix = $shmConfigBase.ipPrefix

    # Deconstruct VNet address prefix to allow easy construction of IP based parameters
    $shmPrefixOctets = $shmPrefix.Split('.')
    $shmBasePrefix = $shmPrefixOctets[0] + "." + $shmPrefixOctets[1]
    $shmThirdOctet = ([int] $shmPrefixOctets[2])

    # --- Top-level config ---
    $shm.subscriptionName = $shmConfigBase.subscriptionName
    $shm.computeVmImageSubscriptionName = $shmConfigBase.computeVmImageSubscriptionName
    $shm.id = $shmConfigBase.shmId
    $shm.name = $shmConfigBase.name
    $shm.organisation = $shmConfigBase.organisation
    $shm.location = $shmConfigBase.location
    $shm.adminSecurityGroupName = $shmConfigBase.adminSecurityGroupName

    # --- Domain config ---
    $shm.domain = [ordered]@{}
    $shm.domain.fqdn = $shmConfigBase.domain
    $netbiosNameMaxLength = 15
    if($shmConfigBase.netbiosName.length -gt $netbiosNameMaxLength) {
        throw "Netbios name must be no more than 15 characters long. '$($shmConfigBase.netbiosName)' is $($shmConfigBase.netbiosName.length) characters long."
    }
    $shm.domain.netbiosName = $shmConfigBase.netbiosName
    $shm.domain.dn = "DC=" + ($shm.domain.fqdn.replace('.',',DC='))
    $shm.domain.serviceServerOuPath = "OU=Safe Haven Service Servers," + $shm.domain.dn
    $shm.domain.serviceOuPath = "OU=Safe Haven Service Accounts," + $shm.domain.dn
    $shm.domain.userOuPath = "OU=Safe Haven Research Users," + $shm.domain.dn
    $shm.domain.securityOuPath = "OU=Safe Haven Security Groups," + $shm.domain.dn
    $shm.domain.securityGroups = [ordered]@{
        dsvmLdapUsers = [ordered]@{}
    }
    $shm.domain.securityGroups.dsvmLdapUsers.name = "SG Data Science LDAP Users"
    $shm.domain.securityGroups.dsvmLdapUsers.description = $shm.domain.securityGroups.dsvmLdapUsers.name


    # --- Network config ---
    $shm.network = [ordered]@{
        vnet = [ordered]@{
            rg = "RG_SHM_VNET"
            name =  "VNET_SHM_" + "$($shm.id)".ToUpper()
            cidr = $shmBasePrefix + "." + $shmThirdOctet + ".0/21"
        }
        subnets = [ordered]@{}
    }
    # --- Identity subnet
    $shm.network.subnets.identity = [ordered]@{}
    $shm.network.subnets.identity.name = "IdentitySubnet" # Name to match required format of GatewaySubnet
    $shm.network.subnets.identity.prefix = $shmBasePrefix + "." + $shmThirdOctet
    $shm.network.subnets.identity.cidr = $shm.network.subnets.identity.prefix + ".0/24"
    # --- Web subnet
    $shm.network.subnets.web = [ordered]@{}
    $shm.network.subnets.web.name = "WebSubnet" # Name to match required format of GatewaySubnet
    $shm.network.subnets.web.prefix = $shmBasePrefix + "." + ([int] $shmThirdOctet + 1)
    $shm.network.subnets.web.cidr = $shm.network.subnets.web.prefix + ".0/24"
    # --- Gateway subnet
    $shm.network.subnets.gateway = [ordered]@{}
    $shm.network.subnets.gateway.name = "GatewaySubnet" # The Gateway subnet MUST be named 'GatewaySubnet' - see https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq#do-i-need-a-gatewaysubnet
    $shm.network.subnets.gateway.prefix = $shmBasePrefix + "." + ([int] $shmThirdOctet + 7)
    $shm.network.subnets.gateway.cidr = $shm.network.subnets.gateway.prefix + ".0/24"


    # --- Domain controller config ---
    $shm.dc = [ordered]@{}
    $shm.dc.rg = "RG_SHM_DC"
    $shm.dc.vmName = "DC1-SHM-" + "$($shm.id)".ToUpper()
    $shm.dc.vmSize = "Standard_DS2_v2"
    $shm.dc.hostname = $shm.dc.vmName
    $shm.dc.fqdn = $shm.dc.hostname + "." + $shm.domain.fqdn
    $shm.dc.ip = $shm.network.subnets.identity.prefix + ".250"

    # Backup AD DC details
    $shm.dcb = [ordered]@{}
    $shm.dcb.vmName = "DC2-SHM-" + "$($shm.id)".ToUpper()
    $shm.dcb.hostname = $shm.dcb.vmName
    $shm.dcb.fqdn = $shm.dcb.hostname + "." + $shm.domain.fqdn
    $shm.dcb.ip = $shm.network.subnets.identity.prefix + ".249"

    # --- NPS config ---
    $shm.nps = [ordered]@{}
    $shm.nps.rg = "RG_SHM_NPS"
    $shm.nps.vmName = "NPS-SHM-" + "$($shm.id)".ToUpper()
    $shm.nps.vmSize = "Standard_DS2_v2"
    $shm.nps.hostname = $shm.nps.vmName
    $shm.nps.ip = $shm.network.subnets.identity.prefix + ".248"

    # --- Storage config --
    $shm.storage = [ordered]@{
        artifacts = [ordered]@{
            rg = "RG_SHM_ARTIFACTS"
            accountName = "shm" + "$($shm.id)".ToLower() + "artifacts"
        }
    }

    # --- Secrets config ---
    $shm.keyVault = [ordered]@{
        rg = "RG_SHM_SECRETS"
        name = "kv-shm-" + "$($shm.id)".ToLower()
    }
    $shm.keyVault.secretNames = [ordered]@{
        aadAdminPassword='shm-aad-admin-password'
        dcNpsAdminUsername='shm-dcnps-admin-username'
        dcNpsAdminPassword='shm-dcnps-admin-password'
        dcSafemodePassword='shm-dc-safemode-password'
        adsyncPassword='shm-adsync-password'
        vpnCaCertificate='shm-vpn-ca-cert'
        vpnCaCertPassword='shm-vpn-ca-cert-password'
        vpnCaCertificatePlain='shm-vpn-ca-cert-plain'
        vpnClientCertificate='shm-vpn-client-cert'
        vpnClientCertPassword='shm-vpn-client-cert-password'
    }

    # --- DNS config ---
    $rgSuffix = ""
    if ($shm.adminSecurityGroupName -like "*Production*") {
        $rgSuffix = "_PRODUCTION"
    } elseif ($shm.adminSecurityGroupName -like "*Test*") {
        $rgSuffix = "_TEST"
    }
    $shm.dns = [ordered]@{
        subscriptionName = $shmConfigBase.domainSubscriptionName
        rg = "RG_SHM_DNS" + $rgSuffix
    }

    # --- Package mirror config ---
    $shm.mirrors = [ordered]@{
        rg = "RG_SHM_PKG_MIRRORS"
    }

    return $shm
}
Export-ModuleMember -Function Get-ShmFullConfig


function TrimToLength {
    param (
        [Parameter(Mandatory=$True,ValueFromPipeline=$True)]
        [string] $str,
        [Parameter(Mandatory=$True,Position=1)]
        [int] $length
    )
    return $str[0..($length-1)] -join ""
}
Export-ModuleMember -Function TrimToLength

# Add a new DSG configuration
# ---------------------------
function Add-SreConfig {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g '9' for DSG9)")]
        $sreId
    )
    $configRootDir = Get-ConfigRootDir
    $dsgCoreConfigFilename = "dsg_" + $sreId + "_core_config.json"
    $dsgCoreConfigPath = Join-Path $configRootDir "core" $dsgCoreConfigFilename -Resolve
    $dsgFullConfigFilename = "dsg_" + $sreId + "_full_config.json"
    $dsgFullConfigPath = Join-Path $configRootDir "full" $dsgFullConfigFilename

    # Import minimal management config parameters from JSON config file - we can derive the rest from these
    $dsgConfigBase = Get-Content -Path $dsgCoreConfigPath -Raw | ConvertFrom-Json

    # Use hash table for config
    $config = [ordered]@{
        shm = Get-ShmFullConfig($dsgConfigBase.shmId)
        dsg = [ordered]@{}
    }

    # === DSG configuration parameters ===
    $dsg = [ordered]@{}
    # Import minimal DSG config parameters from JSON config file - we can derive the rest from these
    $dsgConfigBase = Get-Content -Path $dsgCoreConfigPath -Raw | ConvertFrom-Json
    $dsgPrefix = $dsgConfigBase.ipPrefix

    # Deconstruct VNet address prefix to allow easy construction of IP based parameters
    $dsgPrefixOctets = $dsgPrefix.Split('.')
    $dsgBasePrefix = $dsgPrefixOctets[0] + "." + $dsgPrefixOctets[1]
    $dsgThirdOctet = $dsgPrefixOctets[2]

    # --- Top-level config ---
    $config.dsg.subscriptionName = $dsgConfigBase.subscriptionName
    $config.dsg.id = $dsgConfigBase.dsgId
    $config.dsg.shortName = "sre-" + $dsgConfigBase.dsgId.ToLower()
    $config.dsg.location = $config.shm.location
    $config.dsg.tier = $dsgConfigBase.tier
    $config.dsg.adminSecurityGroupName = $dsgConfigBase.adminSecurityGroupName


    # --- Package mirror config ---
    $config.dsg.mirrors = [ordered]@{
        vnet = [ordered]@{}
        cran = [ordered]@{}
        pypi = [ordered]@{}
    }
    # Tier-2 and Tier-3 mirrors use different IP ranges for their VNets so they can be easily identified
    if(@("2", "3").Contains($config.dsg.tier)){
        $config.dsg.mirrors.vnet.name = "VNET_SHM_" + $($config.shm.id).ToUpper() + "_PKG_MIRRORS_TIER" + $config.dsg.tier
        $config.dsg.mirrors.pypi.ip = "10.20." + $config.dsg.tier + ".20"
        $config.dsg.mirrors.cran.ip = "10.20." + $config.dsg.tier + ".21"
    } elseif(@("0", "1").Contains($config.dsg.tier)) {
        $config.dsg.mirrors.vnet.name = $null
        $config.dsg.mirrors.pypi.ip = $null
        $config.dsg.mirrors.cran.ip = $null
    } else {
        Write-Error ("Tier '" + $config.dsg.tier + "' not supported (NOTE: Tier must be provided as a string in the core DSG config.)")
        return
    }

    # -- Domain config ---
    $config.dsg.domain = [ordered]@{}
    $config.dsg.domain.fqdn = $dsgConfigBase.domain
    $netbiosNameMaxLength = 15
    if($dsgConfigBase.netbiosName.length -gt $netbiosNameMaxLength) {
        throw "Netbios name must be no more than 15 characters long. '$($dsgConfigBase.netbiosName)' is $($dsgConfigBase.netbiosName.length) characters long."
    }
    $config.dsg.domain.netbiosName = $dsgConfigBase.netBiosname
    $config.dsg.domain.dn = "DC=" + ($config.dsg.domain.fqdn.replace('.',',DC='))
    $config.dsg.domain.securityGroups = [ordered]@{
        serverAdmins = [ordered]@{}
        researchUsers = [ordered]@{}
    }
    $config.dsg.domain.securityGroups.serverAdmins.name = ("SG " + $config.dsg.domain.netbiosName + " Server Administrators")
    $config.dsg.domain.securityGroups.serverAdmins.description = $config.dsg.domain.securityGroups.serverAdmins.name
    $config.dsg.domain.securityGroups.researchUsers.name = "SG " + $config.dsg.domain.netbiosName + " Research Users"
    $config.dsg.domain.securityGroups.researchUsers.description = $config.dsg.domain.securityGroups.researchUsers.name

    # --- Network config ---
    $config.dsg.network = [ordered]@{
        vnet = [ordered]@{}
        subnets = [ordered]@{
            identity = [ordered]@{}
            rds = [ordered]@{}
            data = [ordered]@{}
            gateway = [ordered]@{}
        }
        nsg = [ordered]@{
            data = [ordered]@{}
        }
    }
    $config.dsg.network.vnet.rg = "RG_SRE_VNET"
    $config.dsg.network.vnet.name = "VNET_SRE_" + $($config.dsg.id).ToUpper()
    $config.dsg.network.vnet.cidr = $dsgBasePrefix + "." + $dsgThirdOctet + ".0/21"
    $config.dsg.network.subnets.identity.name = "IdentitySubnet"
    $config.dsg.network.subnets.identity.prefix =  $dsgBasePrefix + "." + $dsgThirdOctet
    $config.dsg.network.subnets.identity.cidr = $config.dsg.network.subnets.identity.prefix + ".0/24"
    $config.dsg.network.subnets.rds.name = "RDSSubnet"
    $config.dsg.network.subnets.rds.prefix =  $dsgBasePrefix + "." + ([int] $dsgThirdOctet + 1)
    $config.dsg.network.subnets.rds.cidr = $config.dsg.network.subnets.rds.prefix + ".0/24"
    $config.dsg.network.subnets.data.name = "SharedDataSubnet"
    $config.dsg.network.subnets.data.prefix =  $dsgBasePrefix + "." + ([int] $dsgThirdOctet + 2)
    $config.dsg.network.subnets.data.cidr = $config.dsg.network.subnets.data.prefix + ".0/24"
    $config.dsg.network.subnets.gateway.name = "GatewaySubnet" # The Gateway subnet MUST be named 'GatewaySubnet' - see https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-vpn-faq#do-i-need-a-gatewaysubnet
    $config.dsg.network.subnets.gateway.prefix =  $dsgBasePrefix + "." + ([int] $dsgThirdOctet + 7)
    $config.dsg.network.subnets.gateway.cidr = $config.dsg.network.subnets.gateway.prefix + ".0/27"
    $config.dsg.network.nsg.data.rg = "RG_SRE_WEBAPPS"
    $config.dsg.network.nsg.data.name = "NSG_SRE_WEBAPPS"

    # --- Storage config --
    $config.dsg.storage = [ordered]@{
        artifacts = [ordered]@{}
    }
    $config.dsg.storage.artifacts.rg = "RG_SRE_ARTIFACTS"
    $config.dsg.storage.artifacts.accountName = "sre$($config.dsg.id)artifacts"

    # --- Secrets ---
    $config.dsg.keyVault = [ordered]@{
        name = "kv-" + $config.shm.id + "-sre-" + $($config.dsg.id).ToLower()
        rg = "RG_SRE_SECRETS"
    }
    $config.dsg.keyVault.secretNames = [ordered]@{
        dcAdminPassword = $config.dsg.shortName + '-dc-admin-password'
        dcAdminUsername = $config.dsg.shortName + '-dc-admin-username'
        dsvmAdminPassword = $config.dsg.shortName + "-dsvm-admin-password"
        dsvmAdminUsername = $config.dsg.shortName + "-dsvm-admin-username"
        dsvmDbAdminPassword = $config.dsg.shortName + "-dsvm-pgdb-admin-password"
        dsvmDbReaderPassword = $config.dsg.shortName + "-dsvm-pgdb-reader-password"
        dsvmDbWriterPassword = $config.dsg.shortName + "-dsvm-pgdb-writer-password"
        dsvmLdapPassword = $config.dsg.shortName + "-dsvm-ldap-password"
        gitlabLdapPassword = $config.dsg.shortName + "-gitlab-ldap-password"
        gitlabRootPassword = $config.dsg.shortName + "-gitlab-root-password"
        gitlabUserPassword = $config.dsg.shortName + "-gitlab-user-password"
        hackmdLdapPassword = $config.dsg.shortName + "-hackmd-ldap-password"
        hackmdUserPassword = $config.dsg.shortName + "-hackmd-user-password"
        letsEncryptCertificate = $config.dsg.shortName + "-lets-encrypt-certificate"
        testResearcherPassword = $config.dsg.shortName + "-test-researcher-password"
    }

    # --- Domain controller ---
    $config.dsg.dc = [ordered]@{}
    $config.dsg.dc.rg = "RG_SRE_DC"
    $config.dsg.dc.vmName = "DC-SRE-" + $($config.dsg.id).ToUpper() | TrimToLength 15
    $config.dsg.dc.vmSize = "Standard_DS2_v2"
    $config.dsg.dc.hostname = $config.dsg.dc.vmName
    $config.dsg.dc.fqdn = $config.dsg.dc.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.dc.ip = $config.dsg.network.subnets.identity.prefix + ".250"

    # --- Domain users ---
    $config.dsg.users = [ordered]@{
        ldap = [ordered]@{
            gitlab = [ordered]@{}
            hackmd = [ordered]@{}
            dsvm = [ordered]@{}
        }
        researchers = [ordered]@{
            test = [ordered]@{}
        }
    }
    $config.dsg.users.ldap.gitlab.name = $config.dsg.domain.netbiosName + " Gitlab LDAP"
    $config.dsg.users.ldap.gitlab.samAccountName = "gitlabldap" + $dsgConfigBase.dsgId.ToLower() | TrimToLength 20
    $config.dsg.users.ldap.hackmd.name = $config.dsg.domain.netbiosName + " HackMD LDAP"
    $config.dsg.users.ldap.hackmd.samAccountName = "hackmdldap" + $dsgConfigBase.dsgId.ToLower() | TrimToLength 20
    $config.dsg.users.ldap.dsvm.name = $config.dsg.domain.netbiosName + " DSVM LDAP"
    $config.dsg.users.ldap.dsvm.samAccountName = "dsvmldap" + $dsgConfigBase.dsgId.ToLower() | TrimToLength 20
    $config.dsg.users.researchers.test.name = $config.dsg.domain.netbiosName + " Test Researcher"
    $config.dsg.users.researchers.test.samAccountName = "testresrch" + $dsgConfigBase.dsgId.ToLower() | TrimToLength 20

    # --- RDS Servers ---
    $config.dsg.rds = [ordered]@{
        gateway = [ordered]@{}
        sessionHost1 = [ordered]@{}
        sessionHost2 = [ordered]@{}
    }
    $config.dsg.rds.rg = "RG_SRE_RDS"
    $config.dsg.rds.nsg = [ordered]@{
        gateway = [ordered]@{}
    }
    $config.dsg.rds.nsg.gateway.name = "NSG_RDS-DSG" + $config.dsg.id + "_Server"

    # Set which IPs can access the Safe Haven: if 'default' is given then apply sensible defaults
    if($dsgConfigBase.rdsAllowedSources -eq "default") {
        if(@("3", "4").Contains($config.dsg.tier)) {
            $config.dsg.rds.nsg.gateway.allowedSources = "193.60.220.240"
        } elseif($config.dsg.tier -eq "2") {
            $config.dsg.rds.nsg.gateway.allowedSources = "193.60.220.253"
        } elseif(@("0", "1").Contains($config.dsg.tier)) {
            $config.dsg.rds.nsg.gateway.allowedSources = "Internet"
        }
    } else {
        $config.dsg.rds.nsg.gateway.allowedSources = $dsgConfigBase.rdsAllowedSources
    }
    # Set whether internet access is allowed: if 'default' is given then apply sensible defaults
    if($dsgConfigBase.rdsInternetAccess -eq "default") {
        if(@("2", "3", "4").Contains($config.dsg.tier)) {
            $config.dsg.rds.nsg.gateway.outboundInternet = "Deny"
        } elseif(@("0", "1").Contains($config.dsg.tier)) {
            $config.dsg.rds.nsg.gateway.outboundInternet = "Allow"
        }
    } else {
        $config.dsg.rds.nsg.gateway.outboundInternet = $dsgConfigBase.rdsInternetAccess
    }
    $config.dsg.rds.nsg.sessionHosts.name = "NSG_SessionHosts"
    $config.dsg.rds.gateway.vmName = "RDG-SRE-" + $($config.dsg.id).ToUpper() | TrimToLength 15
    $config.dsg.rds.gateway.vmSize = "Standard_DS2_v2"
    $config.dsg.rds.gateway.hostname = $config.dsg.rds.gateway.vmName
    $config.dsg.rds.gateway.fqdn = $config.dsg.rds.gateway.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.rds.gateway.ip = $config.dsg.network.subnets.rds.prefix + ".250"
    $config.dsg.rds.gateway.npsSecretName = "sre-" + $($config.dsg.id).ToLower() + "-nps-secret"
    $config.dsg.rds.sessionHost1.vmName = "APP-SRE-" + $($config.dsg.id).ToUpper() | TrimToLength 15
    $config.dsg.rds.sessionHost1.vmSize = "Standard_D4s_v3"
    $config.dsg.rds.sessionHost1.hostname = $config.dsg.rds.sessionHost1.vmName
    $config.dsg.rds.sessionHost1.fqdn = $config.dsg.rds.sessionHost1.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.rds.sessionHost1.ip = $config.dsg.network.subnets.rds.prefix + ".249"
    $config.dsg.rds.sessionHost2.vmName = "DKP-SRE-" + $($config.dsg.id).ToUpper() | TrimToLength 15
    $config.dsg.rds.sessionHost2.vmSize = "Standard_D4s_v3"
    $config.dsg.rds.sessionHost2.hostname = $config.dsg.rds.sessionHost2.vmName
    $config.dsg.rds.sessionHost2.fqdn = $config.dsg.rds.sessionHost2.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.rds.sessionHost2.ip = $config.dsg.network.subnets.rds.prefix + ".248"

    # --- Secure servers ---

    # Data server
    $config.dsg.dataserver = [ordered]@{}
    $config.dsg.dataserver.rg = "RG_SRE_DATA"
    $config.dsg.dataserver.vmName = "DSV-SRE-" + $($config.dsg.id).ToUpper() | TrimToLength 15
    $config.dsg.dataserver.vmSize = "Standard_DS2_v2"
    $config.dsg.dataserver.hostname = $config.dsg.dataserver.vmName
    $config.dsg.dataserver.fqdn = $config.dsg.dataserver.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.dataserver.ip = $config.dsg.network.subnets.data.prefix + ".250"

    # HackMD and Gitlab servers
    $config.dsg.linux = [ordered]@{
        gitlab = [ordered]@{}
        hackmd = [ordered]@{}
    }
    $config.dsg.linux.rg = $config.dsg.network.nsg.data.rg
    $config.dsg.linux.nsg = $config.dsg.network.nsg.data.name
    $config.dsg.linux.gitlab.vmName = "GITLAB-SRE-" + $($config.dsg.id).ToUpper()
    $config.dsg.linux.gitlab.vmSize = "Standard_D2s_v3"
    $config.dsg.linux.gitlab.hostname = $config.dsg.linux.gitlab.vmName
    $config.dsg.linux.gitlab.fqdn = $config.dsg.linux.gitlab.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.linux.gitlab.ip = $config.dsg.network.subnets.data.prefix + ".151"
    $config.dsg.linux.hackmd.vmName = "HACKMD-SRE-" + $($config.dsg.id).ToUpper()
    $config.dsg.linux.hackmd.vmSize = "Standard_D2s_v3"
    $config.dsg.linux.hackmd.hostname = $config.dsg.linux.hackmd.vmName
    $config.dsg.linux.hackmd.fqdn = $config.dsg.linux.hackmd.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.linux.hackmd.ip = $config.dsg.network.subnets.data.prefix + ".152"

    # Compute VMs
    $config.dsg.dsvm = [ordered]@{}
    $config.dsg.dsvm.rg = "RG_SRE_COMPUTE"
    $config.dsg.dsvm.vmImageSubscription = $config.shm.computeVmImageSubscriptionName
    $config.shm.Remove("computeVmImageSubscriptionName")
    $config.dsg.dsvm.vmSizeDefault = "Standard_B2ms"
    $config.dsg.dsvm.vmImageType = $dsgConfigBase.computeVmImageType
    $config.dsg.dsvm.vmImageVersion = $dsgConfigBase.computeVmImageVersion
    $config.dsg.dsvm.osdisk = [ordered]@{
        type = "Standard_LRS"
        size_gb = "60"
    }
    $config.dsg.dsvm.datadisk = [ordered]@{
        type = "Standard_LRS"
        size_gb = "512"
    }
    $config.dsg.dsvm.homedisk = [ordered]@{
        type = "Standard_LRS"
        size_gb = "128"
    }

    $jsonOut = ($config | ConvertTo-Json -depth 10)
    # Write-Host $jsonOut
    Out-File -FilePath $dsgFullConfigPath -Encoding "UTF8" -InputObject $jsonOut
}
Export-ModuleMember -Function Add-SreConfig


# Get a SRE configuration
# -----------------------
function Get-SreConfig {
    param(
        [string]$sreId
    )
    # Read DSG config from file
    $configRootDir = Join-Path $(Get-ConfigRootDir) "full" -Resolve;
    $configFilename =  "dsg_" + $sreId + "_full_config.json";
    $configPath = Join-Path $configRootDir $configFilename -Resolve;
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json;
    return $config
}
Export-ModuleMember -Function Get-SreConfig

function Get-DsgConfig {
    param(
        [string]$dsgId
    )
    return Get-SreConfig -dsgId $dsgId
}
Export-ModuleMember -Function Get-DsgConfig
