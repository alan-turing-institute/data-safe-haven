param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
  [string]$sqlServerName,
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter the SQL Server Edition e.g. sqldev or enterprise")]
  [string]$sqlServerEdition,
  [Parameter(Position=3, Mandatory = $true, HelpMessage = "Enter the size of the VM e.g. Standard_GS1 or Standard_GS2")]
  [string]$sqlServerVmSize,
  [Parameter(Position=4, Mandatory = $true, HelpMessage = "Enter the IP address for the VM")]
  [string]$sqlServerIpAddress,
  [Parameter(Position=5, Mandatory = $true, HelpMessage = "Enter whether SSIS should be disabled")]
  [bool]$sqlServerSsisDisabled
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


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
$sreAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlServerAdminPassword
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()


# Create sql server resource group if it does not exist
# ------------------------------------------------------
#$_ = Deploy-ResourceGroup -Name $config.sre.sqlserver.rg -Location $config.sre.location


# Set up the NSG for the sql server
# ----------------------------------
#$nsg = Deploy-NetworkSecurityGroup -Name $config.sre.sqlserver.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
#Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
#                             -Name "Deny_Internet" `
#                             -Description "Deny Outbound Internet Access" `
#                             -Priority 4000 `
#                             -Direction Outbound -Access Deny -Protocol * `
#                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
#                             -DestinationAddressPrefix Internet -DestinationPortRange *


# Deploy sql server from template
# --------------------------------
Add-LogMessage -Level Info "Creating sql server '$sqlServerName' from template..."
$params = @{
    Administrator_Password = (ConvertTo-SecureString $sreAdminPassword -AsPlainText -Force)
    Administrator_User = $sreAdminUsername
    BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
    Sql_Server_Name = $sqlServerName
    Sql_Server_Edition = $sqlServerEdition
    DC_Administrator_Password = (ConvertTo-SecureString $shmDcAdminPassword -AsPlainText -Force)
    DC_Administrator_User = $shmDcAdminUsername
    Domain_Name = $config.shm.domain.fqdn
    IP_Address = $sqlServerIpAddress
    Virtual_Network_Name = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet = $config.sre.network.subnets.sql.name
    VM_Size = $sqlServerVmSize
}
$vmDeployment = Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "customisations" "msssql" "sre-mssql2019-server-template.json") -Params $params -ResourceGroupName $config.sre.dataserver.rg
$internalFqdn = $vmDeployment.Outputs.Items("internalFqdn").Value

# Move SQL Server VM into correct OU
# -----------------------------------
$_ = Set-AzContext -Subscription $config.shm.subscriptionName
Add-LogMessage -Level Info "Adding sql server server VM to correct OUs on SHM DC..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "customisations" "mssql" "create_sqlserver" "scripts" "Move_Sql_Server_VM_Into_OU.ps1"
$params = @{
    shmDn = "`"$($config.shm.domain.dn)`""
    sqlServerHostname = "`"$internalFqdn`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value
$_ = Set-AzContext -Subscription $config.sre.subscriptionName

# Disable SSIS when not required
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "customisations" "mssql" "create_sqlserver" "scripts" "Disable_SSIS_Remote.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $sqlServerName -ResourceGroupName  $config.sre.sqlserver.rg
Write-Output $result.Value

# Set locale, install updates and reboot
# --------------------------------------
Add-LogMessage -Level Info "Updating sql server VM..."
Invoke-WindowsConfigureAndUpdate -VMName $sqlServerName -ResourceGroupName $config.sre.sqlserver.rg -CommonPowershellPath (Join-Path $PSScriptRoot ".." ".." "common")

# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;