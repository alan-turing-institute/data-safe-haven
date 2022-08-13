param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Cryptography -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Check that we are using the correct provider
# --------------------------------------------
if ($config.sre.remoteDesktop.provider -ne "MicrosoftRDS") {
    Add-LogMessage -Level Fatal "You should not be running this script when using remote desktop provider '$($config.sre.remoteDesktop.provider)'"
}


# Disable legacy TLS protocols on RDS Gateway
# -------------------------------------------
Add-LogMessage -Level Info "[ ] Disabling legacy SSL/TLS protocols on RDS Gateway"
$ScriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Disable_Legacy_TLS_Remote.ps1"
$params = @{
    allowedCiphersB64 = (Get-SslCipherSuites)["tls"] | ConvertTo-Json -Depth 99 | ConvertTo-Base64
}
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $ScriptPath -VMName $config.sre.remoteDesktop.gateway.vmName -ResourceGroupName $config.sre.remoteDesktop.rg -Parameter $params


# Reboot RDS Gateway
# ------------------
Start-VM -Name $config.sre.remoteDesktop.gateway.vmName -ResourceGroupName $config.sre.remoteDesktop.rg -ForceRestart


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
