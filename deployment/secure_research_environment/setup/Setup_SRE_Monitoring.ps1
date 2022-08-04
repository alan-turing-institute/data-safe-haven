param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.OperationalInsights -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureAutomation -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzurePrivateDns -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context
# -------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Connect the private DNS zones to all virtual networks in the SRE
# Note that this must be done before connecting the VMs to log analytics to ensure that they use the private link
# ---------------------------------------------------------------------------------------------------------------
foreach ($PrivateZone in (Get-AzPrivateDnsZone -ResourceGroupName $config.shm.network.vnet.rg)) {
    foreach ($virtualNetwork in Get-VirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg) {
        $null = Connect-PrivateDnsToVirtualNetwork -DnsZone $privateZone -VirtualNetwork $virtualNetwork
    }
}


# Get log analytics workspace details
# -----------------------------------
Add-LogMessage -Level Info "[ ] Getting log analytics workspace details..."
try {
    $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
    $workspace = Deploy-LogAnalyticsWorkspace -Name $config.shm.monitoring.loggingWorkspace.name -ResourceGroupName $config.shm.monitoring.rg -Location $config.sre.location
    $workspaceKey = Get-AzOperationalInsightsWorkspaceSharedKey -Name $workspace.Name -ResourceGroup $workspace.ResourceGroupName
    $null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
    Add-LogMessage -Level InfoSuccess "Retrieved log analytics workspace '$($workspace.Name)."
} catch {
    Add-LogMessage -Level Fatal "Failed to retrieve log analytics workspace!" -Exception $_.Exception
}


# Ensure logging agent is installed on all SRE VMs
# ------------------------------------------------
Add-LogMessage -Level Info "[ ] Ensuring logging agent is installed on all SRE VMs..."
$sreResourceGroups = Get-SreResourceGroups -sreConfig $config
try {
    $null = $sreResourceGroups | ForEach-Object { Get-AzVM -ResourceGroup $_.ResourceGroupName } | ForEach-Object {
        Deploy-VirtualMachineMonitoringExtension -VM $_ -WorkspaceId $workspace.CustomerId -WorkspaceKey $workspaceKey.PrimarySharedKey
    }
    Add-LogMessage -Level Success "Ensured that logging agent is installed on all SRE VMs."
} catch {
    Add-LogMessage -Level Fatal "Failed to ensure that logging agent is installed on all SRE VMs!" -Exception $_.Exception
}


# Schedule updates for all connected VMs
# --------------------------------------
$account = Deploy-AutomationAccount -Name $config.shm.monitoring.automationAccount.name -ResourceGroupName $config.shm.monitoring.rg -Location $config.shm.location
$sreQuery = Deploy-AutomationAzureQuery -Account $account -ResourceGroups $sreResourceGroups
# Create Windows VM update schedule
$windowsSchedule = Deploy-AutomationScheduleDaily -Account $account -Name "sre-$($config.sre.id.ToLower())-windows" -Time "02:01" -TimeZone (Get-TimeZone -Id $config.shm.time.timezone.linux)
$null = Register-VmsWithAutomationSchedule -Account $account -DurationHours 2 -Query $sreQuery -Schedule $windowsSchedule -VmType "Windows"
# Create Linux VM update schedule
$linuxSchedule = Deploy-AutomationScheduleDaily -Account $account -Name "sre-$($config.sre.id.ToLower())-linux" -Time "02:01" -TimeZone (Get-TimeZone -Id $config.shm.time.timezone.linux)
$null = Register-VmsWithAutomationSchedule -Account $account -DurationHours 2 -Query $sreQuery -Schedule $linuxSchedule -VmType "Linux"


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
