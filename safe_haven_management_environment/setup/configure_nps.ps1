# param(
#   [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
#   [string]$shmId
# )

# Import-Module Az
# Import-Module $PSScriptRoot/../../common_powershell/Security.psm1 -Force
# Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
# Import-Module $PSScriptRoot/../../common_powershell/GenerateSasToken.psm1 -Force

# # Get DSG config
# # --------------
# $config = Get-ShmFullConfig($shmId)


# # Temporarily switch to DSG subscription
# # --------------------------------------
# $prevContext = Get-AzContext
# Set-AzContext -SubscriptionId $config.subscriptionName;


# # Run configuration script remotely
# # ---------------------------------
# $scriptPath = Join-Path $PSScriptRoot ".." "scripts" "nps" "remote" "Prepare_NPS_Server.ps1"
# $params = @{
#   remoteDir = "`"C:\Installation`""
# }
# $result = Invoke-AzVMRunCommand -ResourceGroupName $config.nps.rg -Name $config.nps.vmName `
#           -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath -Parameter $params;
# Write-Output $result.Value;


# # Switch back to previous subscription
# # ------------------------------------
# Set-AzContext -Context $prevContext;
