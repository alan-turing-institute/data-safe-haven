param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Disable legacy TLS protocols on RDS Gateway
# -------------------------------------------
Add-LogMessage -Level Info "[ ] Disabling legacy SSL/TLS protocols on RDS Gateway"
$ScriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Disable_Legacy_TLS_Remote.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $ScriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg
Write-Output $result.Value


# Reboot RDS Gateway
# ------------------
Enable-AzVM -Name $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext