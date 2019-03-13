
param(
    [string]$mgmt_id,
    [string]$dsg_id
)
$configRootDIr = Join-Path ".." "dsg_configs" -Resolve

$mgmtCoreConfigFilename = "mgmt_" + $mgmt_id + "_core_config.json"  
$mgmtCoreConfigPath = Join-Path $configRootDIr "core" $mgmtCoreConfigFilename -Resolve

$dsgCoreConfigFilename = "dsg_" + $dsg_id + "_core_config.json"  
$dsgCoreConfigPath = Join-Path $configRootDIr "core" $dsgCoreConfigFilename -Resolve

$dsgFullConfigFilename = "dsg_" + $dsg_id + "_full_config.json"  
$dsgFullConfigPath = Join-Path $configRootDIr "full" $dsgFullConfigFilename

# Use hash table for config
$config = @{
    mgmt = @{}
    dsg = @{}
}
# === SH MANAGEMENT CONFIG ===
# Import minimal management config parameters from JSON config file - we can derive the rest from these
$mgmtConfigBase = Get-Content -Path $mgmtCoreConfigPath -Raw | ConvertFrom-Json
Write-Host $mgmtConfigBase
$mgmtPrefix = $mgmtConfigBase.ipPrefix

# Deconstruct VNet address prefix to allow easy construction of IP based parameters
$mgmtPrefixOctets = $mgmtPrefix.Split('.')
$mgmtBasePrefix = $mgmtPrefixOctets[0] + "." + $mgmtPrefixOctets[1]
$mgmtThirdOctet = ([int] $mgmtPrefixOctets[2])

# --- Top-level config ---
$config.mgmt.subscriptionName = $mgmtConfigBase.subscriptionName
$config.mgmt.id = $mgmtConfigBase.shId

# --- Network config ---
$config.mgmt.network = @{
    vnet = @{}
    subnets = @{}
}
$config.mgmt.network.vnet.cidr = $mgmtBasePrefix + "." + $mgmtThirdOctet + ".0/21"
$config.mgmt.network.subnets.identity = @{}
$config.mgmt.network.subnets.identity.prefix = $mgmtBasePrefix + "." + $mgmtThirdOctet
$config.mgmt.network.subnets.identity.cidr = $config.mgmt.network.subnets.identity.prefix + ".0/24"

# --- Domain config ---
$config.mgmt.domain = @{}
$config.mgmt.domain.fqdn = $mgmtConfigBase.domain
$config.mgmt.domain.netbiosName = $config.mgmt.domain.fqdn.Split('.')[0].ToUpper()
$config.mgmt.domain.dn = "DC=" + ($config.mgmt.domain.fqdn.replace('.',',DC='))
$config.mgmt.domain.serviceOuPath = "OU=Safe Haven Service Accounts," + $config.mgmt.domain.dn
$config.mgmt.domain.userOuPath = "OU=Safe Haven Research Users," + $config.mgmt.domain.dn
$config.mgmt.domain.securityOuPath = "OU=Safe Haven Security Groups," + $config.mgmt.domain.dn

# --- Domain controller config ---
$config.mgmt.dc = @{}
$config.mgmt.dc.hostname = $mgmtConfigBase.dcHostname
$config.mgmt.dc.ip = $config.mgmt.network.subnets.identity.prefix + ".250"

# -- Secrets config ---
$config.mgmt.keyVault = @{}
$config.mgmt.keyVault.name = "sh-management-" + $config.mgmt.id
$config.mgmt.keyVault.secretNames = @{}
$config.mgmt.keyVault.secretNames.p2sRootCert= "DSG-P2S-test-RootCert"
$config.mgmt.keyVault.secretNames.p2sClientCert = "DSG-P2S-test-ClientCert"

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
 