param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$context = Set-AzContext -SubscriptionId $config.subscriptionName

$rgFilter = "RG_SHM_$($config.id)*"

# Get Log Analytics Workspace details
# -----------------------------------
$workspace = Get-AzOperationalInsightsWorkspace -Name $config.logging.workspaceName -ResourceGroup $config.logging.rg
$key = Get-AzOperationalInsightsWorkspaceSharedKey -Name $config.logging.workspaceName -ResourceGroup $config.logging.rg

# Ensure logging agent is installed on all SHM VMs
# ------------------------------------------------
Add-LogMessage -Level Info "Ensuring Log Analytics agent is installed on all SHM VMs...'"
$shmResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $rgFilter } | Where-Object { $_.ResourceGroupName -notlike "*WEBAPP*" })
foreach ($resourceGroup in $shmResourceGroups) {
    Add-LogMessage -Level Info "Ensuring Log Analytics agent is installed on all VMs in resource group '$($resourceGroup.ResourceGroupName)'...'"
    & "$PSScriptRoot/../../common/InstallVMInsights.ps1" -WorkspaceId $workspace.CustomerId -WorkspaceKey $key.PrimarySharedKey `
        -ResourceGroup $resourceGroup.ResourceGroupName -SubscriptionId $context.Subscription.Id -WorkspaceRegion $workspace.Location `
        -ReInstall -Approve
    Add-LogMessage -Level Info "Finished ensuring Log Analytics agent is installed on all VMs in resource group '$($resourceGroup.ResourceGroupName)'.'"
}
Add-LogMessage -Level Info "Finished ensuring Log Analytics agent is installed on all SHM VMs."


# Ensure required Windows event logs are collected
# ------------------------------------------------
Add-LogMessage -Level Info "Ensuring required Windows event logs are being collected...'"
$eventLogNames = @(
    "Active Directory Web Services"
    "Directory Service",
    "DFS Replication",
    "DNS Server",
    "Microsoft-Windows-Security-Netlogon/Operational",
    "Microsoft-Windows-Winlogon/Operational",
    "System"
)

foreach ($eventLogName in $eventLogNames) {
    $sourceName = "windows-event-$eventLogName".
        Replace("%","percent").Replace("/","-per-").Replace(" ","-").ToLower()
    $source = Get-AzOperationalInsightsDataSource `
        -ResourceGroupName $config.logging.rg `
        -WorkspaceName $config.logging.workspaceName `
        -Name $sourceName
    if($source) {  
        Add-LogMessage -Level InfoSuccess "Logging already active for '$eventLogName'."  
    } else {
        $null = New-AzOperationalInsightsWindowsEventDataSource `
            -ResourceGroupName $config.logging.rg `
            -WorkspaceName $config.logging.workspaceName `
            -Name $sourceName `
            -EventLogName $eventLogName `
            -CollectErrors `
            -CollectWarnings `
            -CollectInformation
        if($?) {
            Add-LogMessage -Level Success "Logging activated for '$eventLogName'."
        } else {
            Add-LogMessage -Level Fatal "Failed to activate logging for '$eventLogName'!"
        }
    }
}


# Ensure require Windows performance counters are collected
# ---------------------------------------------------------
Add-LogMessage -Level Info "Ensuring required Windows performance counters are being collected...'"
$counters = @(
    @{setName = "LogicalDisk"; counterName = "Avg. Disk sec/Read"},
    @{setName = "LogicalDisk"; counterName = "Avg. Disk sec/Write"},
    @{setName = "LogicalDisk"; counterName = "Current Disk Queue Length"},
    @{setName = "LogicalDisk"; counterName = "Disk Reads/sec"},
    @{setName = "LogicalDisk"; counterName = "Disk Transfers/sec"},
    @{setName = "LogicalDisk"; counterName = "Disk Writes/sec"},
    @{setName = "LogicalDisk"; counterName = "Free Megabytes"},
    @{setName = "Memory"; counterName = "Available MBytes"},
    @{setName = "Memory"; counterName = "% Committed Bytes In Use"},
    @{setName = "LogicalDisk"; counterName = "% Free Space"},
    @{setName = "Processor"; counterName = "% Processor Time"},
    @{setName = "System"; counterName = "Processor Queue Length"}
)
foreach ($counter in $counters) {
    $sourceName = "windows-counter-$($counter.setName)-$($counter.counterName)".
        Replace("%","percent").Replace("/","-per-").Replace(" ","-").ToLower()
    $source = Get-AzOperationalInsightsDataSource `
        -ResourceGroupName $config.logging.rg `
        -WorkspaceName $config.logging.workspaceName `
        -Name $sourceName
    if($source) {
        Add-LogMessage -Level InfoSuccess "Logging already active for '$($counter.setName)/$($counter.counterName)'"
    } else {
        $null = New-AzOperationalInsightsWindowsPerformanceCounterDataSource `
            -ResourceGroupName $config.logging.rg `
            -WorkspaceName $config.logging.workspaceName `
            -ObjectName $counter.setName `
            -InstanceName "*" `
            -CounterName $counter.counterName `
            -IntervalSeconds 60 `
            -Name $sourceName
        if($?) {
            Add-LogMessage -Level Success "Logging activated for '$($counter.setName)/$($counter.counterName)'."
        } else {
            Add-LogMessage -Level Fatal "Failed to activate logging for '$($counter.setName)/$($counter.counterName)'!"
        }
    }
}


# Activate required Intelligence Packs
# ------------------------------------
Add-LogMessage -Level Info "Ensuring required Log Analytics Intelligence Packs are enabled...'"
$packNames = @(
    "AntiMalware",
    "ADReplication",
    "AzureNetworking",
    "AzureNSGAnalytics",
    "Backup",
    "CapacityPerformance",
    "ChangeTracking",
    "DHCPActivity",
    "DnsAnalytics",
    "InternalWindowsEvent",
    "NetFlow",
    "NetworkMonitoring",
    "Security",
    "SecurityCenterFree",
    "SecurityCenterNetworkTraffic",
    "SecurityInsights",
    "ServiceMap",
    "Updates",
    "WindowsDefenderATP",
    "WindowsEventForwarding",
    "WindowsFirewall",
    "WinLog",
    "VMInsights"
)
foreach ($packName in $packNames) {
    $pack = Get-AzOperationalInsightsIntelligencePack `
        -WorkspaceName $config.logging.workspaceName `
        -ResourceGroupName $config.logging.rg | Where-Object { $_.Name -eq $packName }
    if($pack.Enabled) {
        Add-LogMessage -Level InfoSuccess "'$packName' Intelligence Pack already enabled."
    } else {
        $pack = Set-AzOperationalInsightsIntelligencePack `
            -WorkspaceName $config.logging.workspaceName `
            -ResourceGroupName $config.logging.rg `
            -IntelligencePackName $packName -Enabled $true
        if($?) {
            Add-LogMessage -Level Success "'$packName' Intelligence Pack enabled."
        } else {
            Add-LogMessage -Level Fatal "Failed to enable '$packName' Intelligence Pack!"
        }
    }


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
