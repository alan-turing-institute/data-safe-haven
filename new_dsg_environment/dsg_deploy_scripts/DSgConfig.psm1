function Add-DsgConfig {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID ('test' or 'prod')")]
        $shmId,
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g '9' for DSG9)")]
        $dsgId
    )
    $configRootDir = Join-Path $PSScriptRoot ".." "dsg_configs" -Resolve

    $shmCoreConfigFilename = "shm_" + $shmId + "_core_config.json"  
    $shmCoreConfigPath = Join-Path $configRootDir "core" $shmCoreConfigFilename -Resolve

    $dsgCoreConfigFilename = "dsg_" + $dsgId + "_core_config.json"  
    $dsgCoreConfigPath = Join-Path $configRootDir "core" $dsgCoreConfigFilename -Resolve

    $dsgFullConfigFilename = "dsg_" + $dsgId + "_full_config.json"  
    $dsgFullConfigPath = Join-Path $configRootDir "full" $dsgFullConfigFilename

    # Use hash table for config
    $config = @{
        shm = @{}
        dsg = @{}
    }
    # === SH MANAGEMENT CONFIG ===
    # Import minimal management config parameters from JSON config file - we can derive the rest from these
    $shmConfigBase = Get-Content -Path $shmCoreConfigPath -Raw | ConvertFrom-Json
    Write-Host $shmConfigBase
    $shmPrefix = $shmConfigBase.ipPrefix

    # Deconstruct VNet address prefix to allow easy construction of IP based parameters
    $shmPrefixOctets = $shmPrefix.Split('.')
    $shmBasePrefix = $shmPrefixOctets[0] + "." + $shmPrefixOctets[1]
    $shmThirdOctet = ([int] $shmPrefixOctets[2])

    # --- Top-level config ---
    $config.shm.subscriptionName = $shmConfigBase.subscriptionName
    $config.shm.id = $shmConfigBase.shId

    # --- Domain config ---
    $config.shm.domain = @{}
    $config.shm.domain.fqdn = $shmConfigBase.domain
    $config.shm.domain.netbiosName = $config.shm.domain.fqdn.Split('.')[0].ToUpper()
    $config.shm.domain.dn = "DC=" + ($config.shm.domain.fqdn.replace('.',',DC='))
    $config.shm.domain.serviceOuPath = "OU=Safe Haven Service Accounts," + $config.shm.domain.dn
    $config.shm.domain.userOuPath = "OU=Safe Haven Research Users," + $config.shm.domain.dn
    $config.shm.domain.securityOuPath = "OU=Safe Haven Security Groups," + $config.shm.domain.dn
    $config.shm.domain.securityGroups = @{
        dsvmLdapUsers = @{}
    }
    $config.shm.domain.securityGroups.dsvmLdapUsers.name = "SG Data Science LDAP Users" 
    $config.shm.domain.securityGroups.dsvmLdapUsers.description = $config.shm.domain.securityGroups.dsvmLdapUsers.name


    # --- Network config ---
    $config.shm.network = @{
        vnet = @{}
        subnets = @{}
    }
    $config.shm.network.vnet.cidr = $shmBasePrefix + "." + $shmThirdOctet + ".0/21"
    $config.shm.network.subnets.identity = @{}
    $config.shm.network.subnets.identity.prefix = $shmBasePrefix + "." + $shmThirdOctet
    $config.shm.network.subnets.identity.cidr = $config.shm.network.subnets.identity.prefix + ".0/24"

    # --- Domain controller config ---
    $config.shm.dc = @{}
    $config.shm.dc.rg = "RG_DSG_DC"
    $config.shm.dc.vmName = "DC"
    $config.shm.dc.hostname = $shmConfigBase.dcHostname
    $config.shm.dc.ip = $config.shm.network.subnets.identity.prefix + ".250"

    # --- Storage config --
    $config.shm.storage = @{
        artifacts = @{}
    }
    $config.shm.storage.artifacts.rg = "RG_DSG_ARTIFACTS"
    $config.shm.storage.artifacts.accountName = "dsgxartifacts"

    # -- Secrets config ---
    $config.shm.keyVault = @{}
    $config.shm.keyVault.name = "dsg-management-" + $config.shm.id
    $config.shm.keyVault.secretNames = @{}
    $config.shm.keyVault.secretNames.p2sRootCert= "sh-management-p2s-root-cert"

    # === DSG configuration parameters ===
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

    # -- Domain config ---
    $config.dsg.domain = @{}
    $config.dsg.domain.fqdn = $dsgConfigBase.domain
    $config.dsg.domain.netbiosName = $config.dsg.domain.fqdn.Split('.')[0].ToUpper()
    $config.dsg.domain.dn = "DC=" + ($config.dsg.domain.fqdn.replace('.',',DC='))
    $config.dsg.domain.securityGroups = @{
        researchUsers = @{}
    }
    $config.dsg.domain.securityGroups.researchUsers.name = "SG " + $config.dsg.domain.netbiosName + " Research Users"
    $config.dsg.domain.securityGroups.researchUsers.description = $config.dsg.domain.securityGroups.researchUsers.name

    # --- Network config ---
    $config.dsg.network = @{
        vnet = @{}
        subnets = @{
            identity = @{}
            rds = @{}
            data = @{}
            gateway = @{}
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

    # --- Secrets ---
    $config.dsg.keyVault = @{
        name = "dsg-management-" + $config.shm.id # TODO: Once all scripts driven by this config make separate KeyVault per DSG
    }

    # --- Domain controller ---
    $config.dsg.dc = @{}
    $config.dsg.dc.rg = "RG_DSG_DC"
    $config.dsg.dc.vmName = "DSG" + $config.dsg.id + "DC" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_DC"
    $config.dsg.dc.hostname = $config.dsg.dc.vmName
    $config.dsg.dc.ip = $config.dsg.network.subnets.identity.prefix + ".250"
    $config.dsg.dc.admin = @{
        username = "atiadmin"
        passwordSecretName = "dsg" + $config.dsg.id + "-dc-admin-password" # TODO: Current format targeted at using shm keyvault. Update if this changes.
    }

    # --- Domain users ---
    $config.dsg.users = @{
        ldap = @{
            gitlab = @{}
            hackmd = @{}
            dsvm = @{}
        }
        researchers = @{
            test = @{}
        }
    }
    $config.dsg.users.ldap.gitlab.name = $config.dsg.domain.netbiosName + " Gitlab LDAP"
    $config.dsg.users.ldap.gitlab.samAccountName = $config.dsg.domain.netbiosName.ToLower() + "-gitlab-ldap"
    $config.dsg.users.ldap.gitlab.passwordSecretName = $config.dsg.users.ldap.gitlab.samAccountName + "-password"
    $config.dsg.users.ldap.hackmd.name = $config.dsg.domain.netbiosName + " HackMD LDAP"
    $config.dsg.users.ldap.hackmd.samAccountName = $config.dsg.domain.netbiosName.ToLower() + "-hackmd-ldap"
    $config.dsg.users.ldap.hackmd.passwordSecretName = $config.dsg.users.ldap.hackmd.samAccountName + "-password"
    $config.dsg.users.ldap.dsvm.name = $config.dsg.domain.netbiosName + " DSVM LDAP"
    $config.dsg.users.ldap.dsvm.samAccountName = $config.dsg.domain.netbiosName.ToLower() + "-dsvm-ldap"
    $config.dsg.users.ldap.dsvm.passwordSecretName =  $config.dsg.users.ldap.dsvm.samAccountName + "-password"
    $config.dsg.users.researchers.test.name = $config.dsg.domain.netbiosName.ToLower() + " Test Researcher"
    $config.dsg.users.researchers.test.samAccountName = $config.dsg.domain.netbiosName.ToLower() + "-test-researcher"
    $config.dsg.users.researchers.test.passwordSecretName =  $config.dsg.users.researchers.test.samAccountName + "-password"

    # --- RDS Servers ---
    $config.rds = @{
        gateway = @{}
        sessionHost1 = @{}
        sessionHost2 = @{}
    }
    $config.rds.rg = "RG_DSG_RDS"
    $config.rds.gateway.vmName = "RDS" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_RDS"
    $config.rds.gateway.hostname = $config.rds.gateway.vmName
    $config.rds.gateway.ip = $config.dsg.network.subnets.rds.prefix + ".250"
    $config.rds.sessionHost1.vmName = "RDSSH1" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_RDSSH1"
    $config.rds.sessionHost1.hostname = $config.rds.sessionHost1.vmName
    $config.rds.sessionHost1.ip = $config.dsg.network.subnets.rds.prefix + ".249"
    $config.rds.sessionHost2.vmName = "RDSSH2" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_RDSSH2"
    $config.rds.sessionHost2.hostname = $config.rds.sessionHost2.vmName
    $config.rds.sessionHost2.ip = $config.dsg.network.subnets.rds.prefix + ".248"

    # --- Secure servers ---

    # Data server
    $config.dataserver = @{}
    $config.dataserver.rg = "RG_DSG_DATA"
    $config.dataserver.vmName = "DATASERVER" # TODO: Once all scripts driven by this config, change to: $config.dsg.domain.netbiosName + "_DATASERVER"
    $config.dataserver.hostname = $config.dataserver.vmName
    $config.dataserver.ip = $config.dsg.network.subnets.data.prefix + ".250"


    # Gitlab server

    # HackMD server

    # Compute server

    

    $jsonOut = ($config | ConvertTo-Json -depth 10 )
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
