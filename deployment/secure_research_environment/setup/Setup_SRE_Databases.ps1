param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId
)

Import-Module Az
Import-Module SqlServer
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force
# Import-Module $PSScriptRoot/../../common/SqlServers.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -Subscription $config.sre.subscriptionName


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$shmDcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminPassword
$shmDcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.shm.id)admin".ToLower()
$sreAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dataServerAdminPassword
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$sqlAuthUpdateUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUserPassword
$sqlAuthUpdateUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUsername -DefaultValue "sre$($config.sre.id)sqlauthupd".ToLower()



# Create database resource group if it does not exist
# ---------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.databases.rg -Location $config.sre.location


# Create subnets if they do not exist
# -----------------------------------
$virtualNetwork = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
$mssqldevSubnet = Deploy-Subnet -Name $config.sre.network.subnets.mssqldev.name -VirtualNetwork $virtualNetwork -AddressPrefix $config.sre.network.subnets.mssqldev.cidr
$mssqletlSubnet = Deploy-Subnet -Name $config.sre.network.subnets.mssqletl.name -VirtualNetwork $virtualNetwork -AddressPrefix $config.sre.network.subnets.mssqletl.cidr
$mssqldataSubnet = Deploy-Subnet -Name $config.sre.network.subnets.mssqldata.name -VirtualNetwork $virtualNetwork -AddressPrefix $config.sre.network.subnets.mssqldata.cidr


# Create development SQL server from template
# -------------------------------------------
Add-LogMessage -Level Info "Creating the development SQL server from template..."
$params = @{
    Location = $config.sre.location
    Administrator_Password = (ConvertTo-SecureString $sreAdminPassword -AsPlainText -Force)
    Administrator_User = $sreAdminUsername
    DC_Join_Password = (ConvertTo-SecureString $shmDcAdminPassword -AsPlainText -Force)
    DC_Join_User = $shmDcAdminUsername
    Sql_AuthUpdate_UserName = $sqlAuthUpdateUsername
    Sql_AuthUpdate_Password = (ConvertTo-SecureString $sqlAuthUpdateUserPassword -AsPlainText -Force)
    BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
    Sql_Server_Name = $config.sre.databases.mssqldev.name
    Sql_Server_Edition = "sqldev"
    Domain_Name = $config.shm.domain.fqdn
    IP_Address = $config.sre.databases.mssqldev.ip
    SubnetResourceId = $mssqldevSubnet.Id
    VM_Size = $config.sre.databases.mssqldev.vmSize
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-mssql2019-server-template.json") -Params $params -ResourceGroupName $config.sre.databases.rg


# Create ETL SQL server from template
# -----------------------------------
Add-LogMessage -Level Info "Creating the ETL SQL server from template..."
$params = @{
    Location = $config.sre.location
    Administrator_Password = (ConvertTo-SecureString $sreAdminPassword -AsPlainText -Force)
    Administrator_User = $sreAdminUsername
    DC_Join_Password = (ConvertTo-SecureString $shmDcAdminPassword -AsPlainText -Force)
    DC_Join_User = $shmDcAdminUsername
    Sql_AuthUpdate_UserName = $sqlAuthUpdateUsername
    Sql_AuthUpdate_Password = (ConvertTo-SecureString $sqlAuthUpdateUserPassword -AsPlainText -Force)
    BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
    Sql_Server_Name = $config.sre.databases.mssqletl.name
    Sql_Server_Edition = "sqldev"
    Domain_Name = $config.shm.domain.fqdn
    IP_Address = $config.sre.databases.mssqletl.ip
    SubnetResourceId = $mssqletlSubnet.Id
    VM_Size = $config.sre.databases.mssqletl.vmSize
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-mssql2019-server-template.json") -Params $params -ResourceGroupName $config.sre.databases.rg


# Create data SQL server from template
# ------------------------------------
Add-LogMessage -Level Info "Creating the data SQL server from template..."
$params = @{
    Location = $config.sre.location
    Administrator_Password = (ConvertTo-SecureString $sreAdminPassword -AsPlainText -Force)
    Administrator_User = $sreAdminUsername
    DC_Join_Password = (ConvertTo-SecureString $shmDcAdminPassword -AsPlainText -Force)
    DC_Join_User = $shmDcAdminUsername
    Sql_AuthUpdate_UserName = $sqlAuthUpdateUsername
    Sql_AuthUpdate_Password = (ConvertTo-SecureString $sqlAuthUpdateUserPassword -AsPlainText -Force)
    BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
    Sql_Server_Name = $config.sre.databases.mssqldata.name
    Sql_Server_Edition = "sqldev"
    Domain_Name = $config.shm.domain.fqdn
    IP_Address = $config.sre.databases.mssqldata.ip
    SubnetResourceId = $mssqldataSubnet.Id
    VM_Size = $config.sre.databases.mssqldata.vmSize
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-mssql2019-server-template.json") -Params $params -ResourceGroupName $config.sre.databases.rg


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
