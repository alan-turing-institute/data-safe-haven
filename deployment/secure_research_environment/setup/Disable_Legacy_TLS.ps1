param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
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
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $ScriptPath -VMName $config.sre.remoteDesktop.gateway.vmName -ResourceGroupName $config.sre.remoteDesktop.rg


# Reboot RDS Gateway
# ------------------
Start-VM -Name $config.sre.remoteDesktop.gateway.vmName -ResourceGroupName $config.sre.remoteDesktop.rg -ForceRestart


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
