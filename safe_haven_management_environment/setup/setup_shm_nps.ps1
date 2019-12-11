param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Logging.psm1 -Force


# Get SHM config
# --------------
$config = Get-ShmFullConfig($shmId)


# Temporarily switch to DSG subscription
# ---------------------------------
$originalContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;


# Create resource group if it does not exist
# ------------------------------------------
Write-Host -ForegroundColor DarkCyan "Ensuring that resource group '$($config.nps.rg)' exists..."
New-AzResourceGroup -Name $config.nps.rg -Location $config.location -Force


# Retrieve passwords from the keyvault
# ------------------------------------
Write-Host -ForegroundColor DarkCyan "Creating/retrieving user passwords..."
$dcNpsAdminUsername = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcNpsAdminUsername).SecretValueText;
$dcNpsAdminPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcNpsAdminPassword).SecretValueText;


# Deploy NPS from template
# ------------------------
$templateName = "shmnps-template"
Write-Host -ForegroundColor DarkCyan "Deploying template $templateName..."
$params = @{
    Administrator_User = $dcNpsAdminUsername
    Administrator_Password = (ConvertTo-SecureString $dcNpsAdminPassword -AsPlainText -Force)
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
New-AzResourceGroupDeployment -ResourceGroupName $config.nps.rg -TemplateFile $(Join-Path $PSScriptRoot ".." "arm_templates" "shmnps" "$($templateName).json") @params -Verbose -DeploymentDebugLogLevel ResponseContent
$result = $?
LogTemplateOutput -ResourceGroupName $config.dsg.dc.rg -DeploymentName $templateName
if ($result) {
  Write-Host -ForegroundColor DarkGreen " [o] Template deployment succeeded"
} else {
  Write-Host -ForegroundColor DarkRed " [x] Template deployment failed!"
  throw "Template deployment has failed. Please check the error message above before re-running this script."
}


# Run configuration script remotely
# ---------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "shmnps" "remote" "Prepare_NPS_Server.ps1"
$params = @{
  remoteDir = "`"C:\Installation`""
}
$result = Invoke-AzVMRunCommand -Name $config.nps.vmName -ResourceGroupName $config.nps.rg `
                                -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
Write-Output $result.Value;


# Switch back to original subscription
Set-AzContext -Context $originalContext;