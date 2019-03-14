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
# For some reason, passing a JSON string as the -Parameter value for Invoke-AzVMRunCommand
# results in the double quotes in the JSON string being stripped in transit
# Escaping these with a single backslash retains the double quotes but the transferred
# string is truncated. Escaping these with backticks still results in the double quotes
# being stripped in transit, but we can then replace the backticks with double quotes 
# at the other end to recover a valid JSON string.
$configJson = ($config | ConvertTo-Json -depth 10 -Compress).Replace("`"","```"")

Invoke-AzVMRunCommand -ResourceGroupName $config.shm.dc.rg -Name $config.shm.dc.vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter @{configJson=$configJson};

# Switch back to previous subscription
Set-AzContext -Context $prevContext;

