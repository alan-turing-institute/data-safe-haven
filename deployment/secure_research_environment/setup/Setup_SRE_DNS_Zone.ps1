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


# Switch to SHM subscription
# --------------------------
$null = Set-AzContext -Subscription $config.shm.subscriptionName -ErrorAction Stop


# Add SRE DNS zone to SHM
# -----------------------
Add-LogMessage -Level Info "[ ] Adding SRE DNS zone to internal SHM DNS server..."

$params = @{
    SreFqdn = $config.sre.domain.fqdn
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "configure_shm_dc" "scripts" "Create_DNS_Zone_Remote.ps1"
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params


# Switch to domains subscription
# ------------------------------
$null = Set-AzContext -Subscription $config.shm.dns.subscriptionName -ErrorAction Stop


# Create the DNS Zone and set the parent NS records if required
# -------------------------------------------------------------
Set-DnsZoneAndParentNSRecords -DnsZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
