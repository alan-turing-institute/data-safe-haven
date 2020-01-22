param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Security.psm1 -Force


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
$dcNpsAdminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.dcNpsAdminUsername
$dcNpsAdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.dcNpsAdminPassword


# Deploy NPS from template
# ------------------------
Add-LogMessage -Level Info "Deploying network policy server (NPS) from template..."
$templatePath = Join-Path $PSScriptRoot ".." "arm_templates" "shmnps" "shm-nps-template.json"
$params = @{
    Administrator_User = $dcNpsAdminUsername
    Administrator_Password = (ConvertTo-SecureString $dcNpsAdminPassword -AsPlainText -Force)
    BootDiagnostics_Account_Name = $config.bootdiagnostics.accountName
    Virtual_Network_Resource_Group = $config.network.vnet.rg
    Domain_Name = $config.domain.fqdn
    VM_Size = $config.nps.vmSize
    Virtual_Network_Name = $config.network.vnet.name
    Virtual_Network_Subnet = $config.network.subnets.identity.name
    Shm_Id = "$($config.id)".ToLower()
    NPS_VM_Name = $config.nps.vmName
    NPS_Host_Name = $config.nps.hostname
    NPS_IP_Address = $config.nps.ip
    OU_Path = $config.domain.serviceServerOuPath
}
Deploy-ArmTemplate -TemplatePath "$templatePath" -Params $params -ResourceGroupName $config.nps.rg


# Set the OS language to en-GB remotely
# -------------------------------------
Add-LogMessage -Level Info "Setting OS language for: '$($config.nps.vmName)'..."
$scriptPath = Join-Path $PSScriptRoot ".." ".." "common_powershell" "remote" "Set_Windows_Locale.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg
Write-Output $result.Value


# Run configuration script remotely
# ---------------------------------
Add-LogMessage -Level Info "Configuring NPS server '$($config.nps.vmName)'..."
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmnps" "remote" "Prepare_NPS_Server.ps1"
$params = @{
    remoteDir = "`"C:\Installation`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.nps.vmName -ResourceGroupName $config.nps.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
