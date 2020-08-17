param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Mirrors.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName

# Block external DNS resolution for VMs researchers can log onto
# --------------------------------------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "network_configuration" "scripts" "Block_External_DNS_Queries_Remote.ps1"
$params = @{
    sreId         = "`"$($config.sre.id)`""
    sreVirtualNetworkIndex = "`"$(Get-VirtualNetworkIndex -CIDR $config.sre.network.vnet.cidr)`""
    blockedCidrsList  = "`"$($config.sre.network.vnet.subnets.data.cidr)`""
    exceptionCidrsList = "`"$($config.sre.dataserver.ip)/32`""
}
Add-LogMessage -Level Info "Blocking external DNS resolution for researcher accessible VMs on $($config.shm.dc.vmName)..."
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value
Add-LogMessage -Level Info "Blocking external DNS resolution for researcher accessible VMs on $($config.shm.dcb.vmName)..."
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dcb.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext