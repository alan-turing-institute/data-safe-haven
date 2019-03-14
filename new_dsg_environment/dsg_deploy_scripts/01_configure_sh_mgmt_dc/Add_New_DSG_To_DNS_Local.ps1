param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to management subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.shm.subscriptionName;

# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Add_New_DSG_To_DNS_Remote.ps1"

Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter @{"config"=$config};

# Switch back to previous subscription
Set-AzContext -Context $prevContext;

