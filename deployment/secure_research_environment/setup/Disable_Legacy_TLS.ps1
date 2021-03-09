param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID")]
    [string]$sreId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Disable legacy TLS protocols on RDS Gateway
# -------------------------------------------
Add-LogMessage -Level Info "[ ] Disabling legacy SSL/TLS protocols on RDS Gateway"
$ScriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Disable_Legacy_TLS_Remote.ps1"
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $ScriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg


# Reboot RDS Gateway
# ------------------
Start-VM -Name $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg -ForceRestart


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
