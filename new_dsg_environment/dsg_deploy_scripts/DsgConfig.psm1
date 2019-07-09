
function Get-ConfigRootDir{
    $configRootDir = Join-Path (Get-Item $PSScriptRoot).Parent "dsg_configs" -Resolve
    return $configRootDir
}
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
    $shm.id = $shmConfigBase.shId
    $shm.name = $shmConfigBase.name
    $shm.organisation = $shmConfigBase.organisation
    $shm.location = $shmConfigBase.location

    # --- Domain config ---
    $shm.domain = [ordered]@{}
    $shm.domain.fqdn = $shmConfigBase.domain
    $shm.domain.netbiosName = $shm.domain.fqdn.Split('.')[0].ToUpper()
    $shm.domain.dn = "DC=" + ($shm.domain.fqdn.replace('.',',DC='))
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
        vnet = [ordered]@{}
        subnets = [ordered]@{}
    }
    $shm.network.vnet.rg = $shmConfigBase.vnetRgName # TODO: When SHM deployment automated, make this: "RG_DSG_VNET"
    $shm.network.vnet.name = $shmConfigBase.vnetName # TODO: When SHM deployment automated, make this "DSG_" + $shm.domain.netbiosName + "_VNET1"
    $shm.network.vnet.cidr = $shmBasePrefix + "." + $shmThirdOctet + ".0/21"
    $shm.network.subnets.identity = [ordered]@{}
    $shm.network.subnets.identity.prefix = $shmBasePrefix + "." + $shmThirdOctet
    $shm.network.subnets.identity.cidr = $shm.network.subnets.identity.prefix + ".0/24"

    # --- Domain controller config ---
    $shm.dc = [ordered]@{}
    $shm.dc.rg = $shmConfigBase.dcRgName # TODO: When SHM deploy automated, make this "RG_DSG_DC"
    $shm.dc.vmName = $shmConfigBase.dcVmName # When SHM deploy automated, make this "SHMDC1"
    $shm.dc.hostname = $shmConfigBase.dcHostname
    $shm.dc.fqdn = $shm.dc.hostname + "." + $shm.domain.fqdn
    $shm.dc.ip = $shm.network.subnets.identity.prefix + ".250"

    # --- NPS config ---
    $shm.nps = [ordered]@{}
    $shm.nps.ip = $shm.network.subnets.identity.prefix + "." + $shmConfigBase.npsIp

    # --- Storage config --
    $shm.storage = [ordered]@{
        artifacts = [ordered]@{}
    }
    $shm.storage.artifacts.rg = "RG_DSG_ARTIFACTS"
    $shm.storage.artifacts.accountName = $shmConfigBase.artifactStorageAccount # When SHM deploy is automated use: "dsgartifacts" + $shm.id

    # --- Secrets config ---
    $shm.keyVault = [ordered]@{}
    $shm.keyVault.name = "dsg-management-" + $shm.id
    $shm.keyVault.secretNames = [ordered]@{}
    $shm.keyVault.secretNames.p2sRootCert= "sh-management-p2s-root-cert"

    # --- DNS config ---
    $shm.dns = [ordered]@{}
    $shm.dns.rg = "RG_SHM_DNS"

    return $shm
}
Export-ModuleMember -Function Get-ShmFullConfig

function Add-DsgConfig {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g '9' for DSG9)")]
        $dsgId
    )
    $configRootDir = Get-ConfigRootDir
    $dsgCoreConfigFilename = "dsg_" + $dsgId + "_core_config.json"
    $dsgCoreConfigPath = Join-Path $configRootDir "core" $dsgCoreConfigFilename -Resolve
    $dsgFullConfigFilename = "dsg_" + $dsgId + "_full_config.json"
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
    $config.dsg.shortName = "dsg" + $dsgConfigBase.dsgId.ToLower()
    $config.dsg.location = $config.shm.location
    $config.dsg.tier = $dsgConfigBase.tier

    # --- Package mirror config ---
    $config.dsg.mirrors = [ordered]@{
        rg = "RG_SHM_PKG_MIRRORS"
        keyVault = [ordered]@{}
        vnet = [ordered]@{}
        cran = [ordered]@{}
        pypi = [ordered]@{}
    }
    $config.dsg.mirrors.keyVault.name = "kv-shm-pkg-mirrors-" + $config.shm.id
    # Tier-2 and Tier-3 mirrors use different IP ranges for their VNets so they can be easily identified
    if(@("2", "3").Contains($config.dsg.tier)){
        $config.dsg.mirrors.vnet.name = "VNET_SHM_PKG_MIRRORS_TIER" + $config.dsg.tier
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
    $config.dsg.domain.netbiosName = $config.dsg.domain.fqdn.Split('.')[0].ToUpper()
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
    $config.dsg.network.vnet.rg = "RG_DSG_VNET"
    $config.dsg.network.vnet.name = "DSG_" + $config.dsg.domain.netbiosName + "_VNET1"
    $config.dsg.network.vnet.cidr = $dsgBasePrefix + "." + $dsgThirdOctet + ".0/21"
    $config.dsg.network.subnets.identity.name = "Subnet-Identity"
    $config.dsg.network.subnets.identity.prefix =  $dsgBasePrefix + "." + $dsgThirdOctet
    $config.dsg.network.subnets.identity.cidr = $config.dsg.network.subnets.identity.prefix + ".0/24"
    $config.dsg.network.subnets.rds.name = "Subnet-RDS"
    $config.dsg.network.subnets.rds.prefix =  $dsgBasePrefix + "." + ([int] $dsgThirdOctet + 1)
    $config.dsg.network.subnets.rds.cidr = $config.dsg.network.subnets.rds.prefix + ".0/24"
    $config.dsg.network.subnets.data.name = "Subnet-Data"
    $config.dsg.network.subnets.data.prefix =  $dsgBasePrefix + "." + ([int] $dsgThirdOctet + 2)
    $config.dsg.network.subnets.data.cidr = $config.dsg.network.subnets.data.prefix + ".0/24"
    $config.dsg.network.subnets.gateway.prefix =  $dsgBasePrefix + "." + ([int] $dsgThirdOctet + 7)
    $config.dsg.network.subnets.gateway.cidr = $config.dsg.network.subnets.gateway.prefix + ".0/27"
    $config.dsg.network.nsg.data.rg = "RG_DSG_LINUX"
    $config.dsg.network.nsg.data.name = "NSG_Linux_Servers"

    # --- Storage config --
    $config.dsg.storage = [ordered]@{
        artifacts = [ordered]@{}
    }
    $config.dsg.storage.artifacts.rg = "RG_DSG_ARTIFACTS"
    $config.dsg.storage.artifacts.accountName = "dsg$($config.dsg.id)artifacts" 
    
    # --- Secrets ---
    $config.dsg.keyVault = [ordered]@{
        name = "dsg-management-" + $config.shm.id # TODO: Once all scripts driven by this config make separate KeyVault per DSG
    }

    # --- Domain controller ---
    $config.dsg.dc = [ordered]@{}
    $config.dsg.dc.rg = "RG_DSG_DC"
    $config.dsg.dc.vmName = "DSG" + $config.dsg.id + "DC" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_DC"
    $config.dsg.dc.hostname = $config.dsg.dc.vmName
    $config.dsg.dc.fqdn = $config.dsg.dc.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.dc.ip = $config.dsg.network.subnets.identity.prefix + ".250"
    $config.dsg.dc.admin = [ordered]@{
        username = "atiadmin"
        passwordSecretName = "dsg" + $config.dsg.id + "-dc-admin-password" # TODO: Current format targeted at using shm keyvault. Update if this changes.
    }

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
    $config.dsg.users.ldap.gitlab.samAccountName = $config.dsg.shortName + "-gitlab-ldap"
    $config.dsg.users.ldap.gitlab.passwordSecretName = $config.dsg.users.ldap.gitlab.samAccountName + "-password"
    $config.dsg.users.ldap.hackmd.name = $config.dsg.domain.netbiosName + " HackMD LDAP"
    $config.dsg.users.ldap.hackmd.samAccountName = $config.dsg.shortName + "-hackmd-ldap"
    $config.dsg.users.ldap.hackmd.passwordSecretName = $config.dsg.users.ldap.hackmd.samAccountName + "-password"
    $config.dsg.users.ldap.dsvm.name = $config.dsg.domain.netbiosName + " DSVM LDAP"
    $config.dsg.users.ldap.dsvm.samAccountName = $config.dsg.shortName + "-dsvm-ldap"
    $config.dsg.users.ldap.dsvm.passwordSecretName =  $config.dsg.users.ldap.dsvm.samAccountName + "-password"
    $config.dsg.users.researchers.test.name = $config.dsg.domain.netbiosName + " Test Researcher"
    $config.dsg.users.researchers.test.samAccountName = $config.dsg.shortName + "-test-res"
    $config.dsg.users.researchers.test.passwordSecretName =  $config.dsg.users.researchers.test.samAccountName + "-password"

    # --- RDS Servers ---
    $config.dsg.rds = [ordered]@{
        gateway = [ordered]@{}
        sessionHost1 = [ordered]@{}
        sessionHost2 = [ordered]@{}
    }
    $config.dsg.rds.rg = "RG_DSG_RDS"
    $config.dsg.rds.nsg = [ordered]@{
        gateway = [ordered]@{}
        sessionHosts = [ordered]@{}
    }
    $config.dsg.rds.nsg.gateway.name = "NSG_RDS_Server"
    $config.dsg.rds.nsg.gateway.allowedSources = $dsgConfigBase.rdsAllowedSources
    $config.dsg.rds.nsg.sessionHosts.name = "NSG_SessionHosts"
    $config.dsg.rds.gateway.vmName = "RDS" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_RDS"
    $config.dsg.rds.gateway.hostname = $config.dsg.rds.gateway.vmName
    $config.dsg.rds.gateway.fqdn = $config.dsg.rds.gateway.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.rds.gateway.ip = $config.dsg.network.subnets.rds.prefix + ".250"
    $config.dsg.rds.sessionHost1.vmName = "RDSSH1" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_RDSSH1"
    $config.dsg.rds.sessionHost1.hostname = $config.dsg.rds.sessionHost1.vmName
    $config.dsg.rds.sessionHost1.fqdn = $config.dsg.rds.sessionHost1.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.rds.sessionHost1.ip = $config.dsg.network.subnets.rds.prefix + ".249"
    $config.dsg.rds.sessionHost2.vmName = "RDSSH2" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_RDSSH2"
    $config.dsg.rds.sessionHost2.hostname = $config.dsg.rds.sessionHost2.vmName
    $config.dsg.rds.sessionHost2.fqdn = $config.dsg.rds.sessionHost2.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.rds.sessionHost2.ip = $config.dsg.network.subnets.rds.prefix + ".248"

    # --- Secure servers ---

    # Data server
    $config.dsg.dataserver = [ordered]@{}
    $config.dsg.dataserver.rg = "RG_DSG_DATA"
    $config.dsg.dataserver.vmName = "DATASERVER" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_DATASERVER"
    $config.dsg.dataserver.hostname = $config.dsg.dataserver.vmName
    $config.dsg.dataserver.fqdn = $config.dsg.dataserver.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.dataserver.ip = $config.dsg.network.subnets.data.prefix + ".250"

    # HackMD and Gitlab servers
    $config.dsg.linux = [ordered]@{
        gitlab = [ordered]@{}
        hackmd = [ordered]@{}
    }
    $config.dsg.linux.rg = "RG_DSG_LINUX"
    $config.dsg.linux.nsg = "NSG_Linux_Servers"
    $config.dsg.linux.gitlab.vmName = "GITLAB" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_GITLAB"
    $config.dsg.linux.gitlab.hostname = $config.dsg.linux.gitlab.vmName
    $config.dsg.linux.gitlab.fqdn = $config.dsg.linux.gitlab.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.linux.gitlab.ip = $config.dsg.network.subnets.data.prefix + ".151"
    $config.dsg.linux.gitlab.rootPasswordSecretName = "dsg" + $config.dsg.id + "-gitlab-root-password"
    $config.dsg.linux.hackmd.vmName = "HACKMD" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_HACKMD"
    $config.dsg.linux.hackmd.hostname = $config.dsg.linux.hackmd.vmName
    $config.dsg.linux.hackmd.fqdn = $config.dsg.linux.hackmd.hostname + "." + $config.dsg.domain.fqdn
    $config.dsg.linux.hackmd.ip = $config.dsg.network.subnets.data.prefix + ".152"

    # Compute VMs
    $config.dsg.dsvm = [ordered]@{}
    $config.dsg.dsvm.rg = "RG_DSG_COMPUTE"
    $config.dsg.dsvm.vmImageSubscription =  $config.shm.computeVmImageSubscriptionName
    $config.shm.Remove("computeVmImageSubscriptionName")
    $config.dsg.dsvm.vmImageType = $dsgConfigBase.computeVmImageType
    $config.dsg.dsvm.vmImageVersion = $dsgConfigBase.computeVmImageVersion
    $config.dsg.dsvm.admin = [ordered]@{
        username = "atiadmin"
        passwordSecretName = "dsgroup" + $config.dsg.id + "-dsvm-admin-password" # TODO: Current format targeted at using shm keyvault. Update if this changes.
    }

    $jsonOut = ($config | ConvertTo-Json -depth 10)
    Write-Host $jsonOut
    Out-File -FilePath $dsgFullConfigPath -Encoding "UTF8" -InputObject $jsonOut
}
Export-ModuleMember -Function Add-DsgConfig

function Get-DsgConfig {
    param(
        [string]$dsgId
    )
    # Read DSG config from file
    $configRootDir = Join-Path $PSScriptRoot ".." "dsg_configs" "full" -Resolve;
    $configFilename =  "dsg_" + $dsgId + "_full_config.json";
    $configPath = Join-Path $configRootDir $configFilename -Resolve;
    $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json;
    return $config
}
Export-ModuleMember -Function Get-DsgConfig
