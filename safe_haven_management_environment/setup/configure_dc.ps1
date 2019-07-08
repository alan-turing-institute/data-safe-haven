param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/GeneratePassword.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/GenerateSasToken.psm1 -Force

# Get DSG config
$config = Get-ShmFullConfig($shmId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;


# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "scripts" "dc" "SHM_DC" "Set_OS_Language.ps1"

# For some reason, passing a JSON string as the -Parameter value for Invoke-AzVMRunCommand
# results in the double quotes in the JSON string being stripped in transit
# Escaping these with a single backslash retains the double quotes but the transferred
# string is truncated. Escaping these with backticks still results in the double quotes
# being stripped in transit, but we can then replace the backticks with double quotes 
# at the other end to recover a valid JSON string.
# $configJson = ($config | ConvertTo-Json -depth 10 -Compress).Replace("`"","```"")


$result= Invoke-AzVMRunCommand -ResourceGroupName $config.dc.rg -Name SHMDC1 `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath;

Write-Output $result.Value;
# # Switch back to previous subscription
Set-AzContext -Context $prevContext;

