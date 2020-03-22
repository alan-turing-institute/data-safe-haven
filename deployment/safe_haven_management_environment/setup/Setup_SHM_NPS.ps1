param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig ($shmId)
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# Create resource group if it does not exist
# ------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.nps.rg -Location $config.location


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.keyVault.name)'..."
$shmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.vmAdminUsername -defaultValue "shm$($config.id)admin".ToLower()
$domainAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.domainAdminPassword
$npsAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.npsAdminPassword


# Deploy NPS from template
# ------------------------
Add-LogMessage -Level Info "Deploying network policy server (NPS) from template..."
$params = @{
    Administrator_Password = (ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force)
    Administrator_User = $shmAdminUsername
    BootDiagnostics_Account_Name = $config.storage.bootdiagnostics.accountName
    DC_Administrator_Password = (ConvertTo-SecureString $domainAdminPassword -AsPlainText -Force)
    DC_Administrator_User = $shmAdminUsername
    Domain_Name = $config.domain.fqdn
    NPS_Host_Name = $config.nps.hostname
    NPS_IP_Address = $config.nps.ip
    NPS_VM_Name = $config.nps.vmName
    OU_Path = $config.domain.serviceServerOuPath
    Virtual_Network_Name = $config.network.vnet.name
    Virtual_Network_Resource_Group = $config.network.vnet.rg
    Virtual_Network_Subnet = $config.network.subnets.identity.name
    VM_Size = $config.nps.vmSize
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "shm-nps-template.json") -Params $params -ResourceGroupName $config.nps.rg


# Install required Powershell packages
# ------------------------------------
Add-LogMessage -Level Info "Installing required Powershell packages on: '$($config.nps.vmName)'..."
$scriptPath = Join-Path $PSScriptRoot ".." ".." "common" "remote" "Install_Powershell_Modules.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg
Write-Output $result.Value


# Set the OS language to en-GB and install updates
# ------------------------------------------------
Add-LogMessage -Level Info "Setting OS language for: '$($config.nps.vmName)' and installing updates..."
$scriptPath = Join-Path $PSScriptRoot ".." ".." "common" "remote" "Configure_Windows.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg
Write-Output $result.Value


# Run configuration script remotely
# ---------------------------------
Add-LogMessage -Level Info "Configuring NPS server '$($config.nps.vmName)'..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_nps" "scripts" "Prepare_NPS_Server.ps1"
$params = @{
    remoteDir = "`"C:\Installation`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg -Parameter $params
Write-Output $result.Value


# Restart the NPS server
# ----------------------
Add-LogMessage -Level Info "Restarting $($config.nps.vmName)..."
Enable-AzVM -Name $config.nps.vmName -ResourceGroupName $config.nps.rg
if ($?) {
    Add-LogMessage -Level Success "Restarting NPS $($config.nps.vmName) succeeded"
} else {
    Add-LogMessage -Level Fatal "Restarting NPS $($config.nps.vmName) failed!"
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
