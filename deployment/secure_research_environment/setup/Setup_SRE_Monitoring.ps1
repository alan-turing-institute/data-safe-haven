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
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureOperationalInsights -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzurePrivateDns -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
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
$localTimeZone = Get-TimeZone -Id $config.shm.time.timezone.linux
# Create Windows VM virus definitions update schedule
$windowsDailySchedule = Deploy-AutomationScheduleInDays -Account $account `
                                                        -Name "sre-$($config.sre.id)-windows-definitions".ToLower() `
                                                        -Time "$($config.shm.monitoring.schedule.daily_definition_updates.hour):$($config.shm.monitoring.schedule.daily_definition_updates.minute)" `
                                                        -TimeZone $localTimeZone
$null = Register-VmsWithAutomationSchedule -Account $account `
                                           -DurationHours 1 `
                                           -IncludedUpdateCategories @("Definition") `
                                           -Query $sreQuery `
                                           -Schedule $windowsDailySchedule `
                                           -VmType "Windows"
# Create Windows VM other updates schedule
$windowsWeeklySchedule = Deploy-AutomationScheduleInDays -Account $account `
                                                         -DayInterval 7 `
                                                         -Name "sre-$($config.sre.id)-windows-other".ToLower() `
                                                         -StartDayOfWeek "Tuesday" `
                                                         -Time "$($config.shm.monitoring.schedule.weekly_system_updates.hour):$($config.shm.monitoring.schedule.weekly_system_updates.minute)" `
                                                         -TimeZone $localTimeZone
$null = Register-VmsWithAutomationSchedule -Account $account `
                                           -DurationHours 3 `
                                           -IncludedUpdateCategories @("Critical", "FeaturePack", "Security", "ServicePack", "Tools", "Unclassified", "UpdateRollup", "Updates") `
                                           -Query $sreQuery `
                                           -Schedule $windowsWeeklySchedule `
                                           -VmType "Windows"
# Create Linux VM update schedule
$linuxWeeklySchedule = Deploy-AutomationScheduleInDays -Account $account `
                                                       -DayInterval 7 `
                                                       -Name "sre-$($config.sre.id)-linux".ToLower() `
                                                       -StartDayOfWeek "Tuesday" `
                                                       -Time "$($config.shm.monitoring.schedule.weekly_system_updates.hour):$($config.shm.monitoring.schedule.weekly_system_updates.minute)" `
                                                       -TimeZone $localTimeZone
$null = Register-VmsWithAutomationSchedule -Account $account `
                                           -DurationHours 3 `
                                           -IncludedUpdateCategories @("Critical", "Other", "Security", "Unclassified") `
                                           -Query $sreQuery `
                                           -Schedule $linuxWeeklySchedule `
                                           -VmType "Linux"


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
