param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../GeneratePassword.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to management subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;

$helperScripDir = Join-Path $PSScriptRoot "helper_scripts" "Remove_DSG_Data_From_SHM" 

# === Remove DSG DNS records from SHM DC ===
$scriptPath = Join-Path $helperScripDir "remote_scripts" "Remove_DNS_Entries_Remote.ps1"
$params = @{
  dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
  identitySubnetPrefix = "`"$($config.dsg.network.subnets.identity.prefix)`""
  rdsSubnetPrefix = "`"$($config.dsg.network.subnets.rds.prefix)`""
  dataSubnetPrefix = "`"$($config.dsg.network.subnets.data.prefix)`""
}
Write-Host "Removing DSG DNS records from SHM"
Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;
