
param(
    [string]$shm_id,
    [string]$dsg_id
)
$configRootDIr = Join-Path ".." "dsg_configs" -Resolve

$shmCoreConfigFilename = "shm_" + $shm_id + "_core_config.json"  
$shmCoreConfigPath = Join-Path $configRootDIr "core" $shmCoreConfigFilename -Resolve

$dsgCoreConfigFilename = "dsg_" + $dsg_id + "_core_config.json"  
$dsgCoreConfigPath = Join-Path $configRootDIr "core" $dsgCoreConfigFilename -Resolve

$dsgFullConfigFilename = "dsg_" + $dsg_id + "_full_config.json"  
$dsgFullConfigPath = Join-Path $configRootDIr "full" $dsgFullConfigFilename

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

# --- Network config ---
$config.shm.network = @{
    vnet = @{}
    subnets = @{}
}
$config.shm.network.vnet.cidr = $shmBasePrefix + "." + $shmThirdOctet + ".0/21"
$config.shm.network.subnets.identity = @{}
$config.shm.network.subnets.identity.prefix = $shmBasePrefix + "." + $shmThirdOctet
$config.shm.network.subnets.identity.cidr = $config.shm.network.subnets.identity.prefix + ".0/24"

# --- Domain config ---
$config.shm.domain = @{}
$config.shm.domain.fqdn = $shmConfigBase.domain
$config.shm.domain.netbiosName = $config.shm.domain.fqdn.Split('.')[0].ToUpper()
$config.shm.domain.dn = "DC=" + ($config.shm.domain.fqdn.replace('.',',DC='))
$config.shm.domain.serviceOuPath = "OU=Safe Haven Service Accounts," + $config.shm.domain.dn
$config.shm.domain.userOuPath = "OU=Safe Haven Research Users," + $config.shm.domain.dn
$config.shm.domain.securityOuPath = "OU=Safe Haven Security Groups," + $config.shm.domain.dn

# --- Domain controller config ---
$config.shm.dc = @{}
$config.shm.dc.hostname = $shmConfigBase.dcHostname
$config.shm.dc.ip = $config.shm.network.subnets.identity.prefix + ".250"

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
$config.dsg.network.vnet.cidr = $dsgBasePrefix + "." + $dsgThirdOctet + ".0/21"
$config.dsg.network.subnets.identity.prefix =  $dsgBasePrefix + "." + $dsgThirdOctet
$config.dsg.network.subnets.identity.cidr = $config.dsg.network.subnets.identity.prefix + ".0/24"
$config.dsg.network.subnets.rds.prefix =  $dsgBasePrefix + "." + ([int] $dsgThirdOctet + 1)
$config.dsg.network.subnets.rds.cidr = $config.dsg.network.subnets.rds.prefix + ".0/24"
$config.dsg.network.subnets.data.prefix =  $dsgBasePrefix + "." + ([int] $dsgThirdOctet + 2)
$config.dsg.network.subnets.data.cidr = $config.dsg.network.subnets.data.prefix + ".0/24" 
$config.dsg.network.subnets.gateway.prefix =  $dsgBasePrefix + "." + ([int] $dsgThirdOctet + 7)
$config.dsg.network.subnets.gateway.cidr = $config.dsg.network.subnets.rds.prefix + ".0/24"

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

# --- Domain controller ---
$config.dsg.dc = @{}
$config.dsg.dc.hostname = $config.dsg.domain.netbiosName + "_DC"
$config.dsg.dc.ip = $config.dsg.network.subnets.identity.prefix + ".250"

# --- Users ---
$config.dsg.users = @{
    ldap = @{
        gitlab = @{}
        hackmd = @{}
        dsvm = @{}
    }
    research = @{}
}
$config.dsg.users.ldap.gitlab.name = $config.dsg.domain.netbiosName + " Gitlab LDAP"
$config.dsg.users.ldap.gitlab.samAccountName = $config.dsg.domain.netbiosName.ToLower() + "_gitlab_ldap"
$config.dsg.users.ldap.hackmd.name = $config.dsg.domain.netbiosName + " HackMD LDAP"
$config.dsg.users.ldap.hackmd.samAccountName = $config.dsg.domain.netbiosName.ToLower() + "_hackmd_ldap"
$config.dsg.users.ldap.dsvm.name = $config.dsg.domain.netbiosName + " DSVM LDAP"
$config.dsg.users.ldap.dsvm.samAccountName = $config.dsg.domain.netbiosName.ToLower() + "_dsvm_ldap"
# --- Secure servers ---

# Data server

# Gitlab server

# HackMD server

# Compute server

# --- RDS Servers ---

Write-Host ($config | ConvertTo-Json -depth 10 )
Out-File -FilePath $dsgFullConfigPath -Encoding "UTF8" -InputObject ($config | ConvertTo-Json)
 