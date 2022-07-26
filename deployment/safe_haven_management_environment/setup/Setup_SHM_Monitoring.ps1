param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.OperationalInsights -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureAutomation -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Create resource group if it does not exist
# ------------------------------------------
$null = Deploy-ResourceGroup -Name $config.monitoring.rg -Location $config.location


# Deploy Log Analytics workspace
# ------------------------------
$workspace = Deploy-LogAnalyticsWorkspace -Name $config.monitoring.loggingWorkspace.name -ResourceGroupName $config.monitoring.rg -Location $config.location
$workspaceKey = Get-AzOperationalInsightsWorkspaceSharedKey -Name $workspace.Name -ResourceGroup $workspace.ResourceGroupName


# Deploy automation account
# -------------------------
$account = Deploy-AutomationAccount -Name $config.monitoring.automationAccount.name -ResourceGroupName $config.monitoring.rg -Location $config.location
$null = Connect-AutomationAccountLogAnalytics -AutomationAccountName $account.AutomationAccountName -LogAnalyticsWorkspace $workspace
$null = Deploy-LogAnalyticsSolution -Workspace $workspace -SolutionType "Updates"


# Ensure all SHM VMs are registered with the logging workspace
# This will also ensure they are registered for update management
# ---------------------------------------------------------------
$rgFilter = "RG_SHM_$($config.id)*"
$shmResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $rgFilter } | Where-Object { $_.ResourceGroupName -notlike "*WEBAPP*" })
$VMs = @{ "Windows" = @(); "Linux" = @() }
foreach ($shmResourceGroup in $shmResourceGroups) {
    foreach ($vm in $(Get-AzVM -ResourceGroup $shmResourceGroup.ResourceGroupName)) {
        $null = Deploy-VirtualMachineMonitoringExtension -VM $vm -WorkspaceId $workspace.CustomerId -WorkspaceKey $workspaceKey.PrimarySharedKey
        if ($null -ne $vm.OSProfile.LinuxConfiguration) {
            $VMs["Linux"] += $VM
        } elseif ($null -ne $vm.OSProfile.WindowsConfiguration) {
            $VMs["Windows"] += $VM
        }
    }
}


# Create Windows and Linux update schedules
# -----------------------------------------
# Register Windows VMs
$windowsSchedule = Deploy-AutomationScheduleDaily -Account $account -Name "WindowsUpdate" -Time "02:01" -TimeZone (Get-TimeZone -Id $config.time.timezone.linux)
$null = Register-VmsWithAutomationSchedule -Account $account -DurationHours 2 -Schedule $windowsSchedule -VmIds ($VMs["Windows"] | ForEach-Object { $_.Id }) -VmType "Windows"
# Register Linux VMs
$linuxSchedule = Deploy-AutomationScheduleDaily -Account $account -Name "LinuxUpdate" -Time "02:01" -TimeZone (Get-TimeZone -Id $config.time.timezone.linux)
$null = Register-VmsWithAutomationSchedule -Account $account -DurationHours 2 -Schedule $linuxSchedule -VmIds ($VMs["Linux"] | ForEach-Object { $_.Id }) -VmType "Linux"


# Enable the collection of syslog logs from Linux hosts
# -----------------------------------------------------
# Syslog facilities:
#   See
#     - https://wiki.gentoo.org/wiki/Rsyslog#Facility
#     - https://tools.ietf.org/html/rfc5424 (page 10)
#     - https://rsyslog.readthedocs.io/en/latest/configuration/filters.html
$null = Enable-AzOperationalInsightsLinuxSyslogCollection -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name
$facilities = @{
    "auth"     = "security/authorization messages";
    "authpriv" = "non-system authorization messages";
    "cron"     = "clock daemon";
    "daemon"   = "system daemons";
    "ftp"      = "FTP daemon";
    "kern"     = "kernel messages";
    "lpr"      = "line printer subsystem";
    "mail"     = "mail system";
    "news"     = "network news subsystem";
    "syslog"   = "messages generated internally by syslogd";
    "user"     = "user-level messages";
    "uucp"     = "UUCP subsystem";
}
# Delete all existing syslog sources
$sources = Get-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Kind 'LinuxSysLog'
foreach ($source in $sources) {
    $null = Remove-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Name $source.Name -Force
}
# Syslog severities:
#   See
#     - https://wiki.gentoo.org/wiki/Rsyslog#Severity
#     - https://tools.ietf.org/html/rfc5424 (page 11)
#
#   Emergency:     system is unusable
#   Alert:         action must be taken immediately
#   Critical:      critical conditions
#   Error:         error conditions
#   Warning:       warning conditions
#   Notice:        normal but significant condition
#   Informational: informational messages
#   Debug:         debug-level messages
foreach ($facility in $facilities.GetEnumerator()) {
    $null = New-AzOperationalInsightsLinuxSyslogDataSource -CollectAlert `
                                                           -CollectCritical `
                                                           -CollectDebug `
                                                           -CollectEmergency `
                                                           -CollectError `
                                                           -CollectInformational `
                                                           -CollectNotice `
                                                           -CollectWarning `
                                                           -Facility $facility.Key `
                                                           -Force `
                                                           -Name "Linux-syslog-$($facility.Key)" `
                                                           -ResourceGroupName $workspace.ResourceGroupName `
                                                           -WorkspaceName $workspace.Name
    if ($?) {
        Add-LogMessage -Level Success "Logging activated for '$($facility.Key)' syslog facility [$($facility.Value)]."
    } else {
        Add-LogMessage -Level Fatal "Failed to activate logging for '$($facility.Key)' syslog facility [$($facility.Value)]!"
    }
}


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

# Delete all existing event log sources
$sources = Get-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Kind 'WindowsEvent'
foreach ($source in $sources) {
    $null = Remove-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Name $source.Name -Force
}

foreach ($eventLogName in $eventLogNames) {
    $sourceName = "windows-event-$eventLogName".Replace("%", "percent").Replace("/", "-per-").Replace(" ", "-").ToLower()
    $null = New-AzOperationalInsightsWindowsEventDataSource -CollectErrors `
                                                            -CollectInformation `
                                                            -CollectWarnings `
                                                            -EventLogName $eventLogName `
                                                            -Name $sourceName `
                                                            -ResourceGroupName $workspace.ResourceGroupName `
                                                            -WorkspaceName $workspace.Name
    if ($?) {
        Add-LogMessage -Level Success "Logging activated for '$eventLogName'."
    } else {
        Add-LogMessage -Level Fatal "Failed to activate logging for '$eventLogName'!"
    }
}


# Ensure require Windows performance counters are collected
# ---------------------------------------------------------
Add-LogMessage -Level Info "Ensuring required Windows performance counters are being collected...'"
$counters = @(
    @{setName = "LogicalDisk"; counterName = "Avg. Disk sec/Read" },
    @{setName = "LogicalDisk"; counterName = "Avg. Disk sec/Write" },
    @{setName = "LogicalDisk"; counterName = "Current Disk Queue Length" },
    @{setName = "LogicalDisk"; counterName = "Disk Reads/sec" },
    @{setName = "LogicalDisk"; counterName = "Disk Transfers/sec" },
    @{setName = "LogicalDisk"; counterName = "Disk Writes/sec" },
    @{setName = "LogicalDisk"; counterName = "Free Megabytes" },
    @{setName = "Memory"; counterName = "Available MBytes" },
    @{setName = "Memory"; counterName = "% Committed Bytes In Use" },
    @{setName = "LogicalDisk"; counterName = "% Free Space" },
    @{setName = "Processor"; counterName = "% Processor Time" },
    @{setName = "System"; counterName = "Processor Queue Length" }
)

# Delete all existing performance counter log sources
$sources = Get-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Kind 'WindowsPerformanceCounter'
foreach ($source in $sources) {
    $null = Remove-AzOperationalInsightsDataSource -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name -Name $source.Name -Force
}

foreach ($counter in $counters) {
    $sourceName = "windows-counter-$($counter.setName)-$($counter.counterName)".Replace("%", "percent").Replace("/", "-per-").Replace(" ", "-").ToLower()
    $null = New-AzOperationalInsightsWindowsPerformanceCounterDataSource -CounterName $counter.counterName `
                                                                         -InstanceName "*" `
                                                                         -IntervalSeconds 60 `
                                                                         -Name $sourceName `
                                                                         -ObjectName $counter.setName `
                                                                         -ResourceGroupName $workspace.ResourceGroupName `
                                                                         -WorkspaceName $workspace.Name
    if ($?) {
        Add-LogMessage -Level Success "Logging activated for '$($counter.setName)/$($counter.counterName)'."
    } else {
        Add-LogMessage -Level Fatal "Failed to activate logging for '$($counter.setName)/$($counter.counterName)'!"
    }
}


# Activate required Intelligence Packs
# ------------------------------------
Add-LogMessage -Level Info "Ensuring required Log Analytics Intelligence Packs are enabled...'"
$packNames = @(
    "AgentHealthAssessment",
    "AzureActivity",
    "AzureNetworking",
    "AzureResources",
    "AntiMalware",
    "CapacityPerformance",
    "ChangeTracking",
    "DnsAnalytics",
    "InternalWindowsEvent",
    "LogManagement",
    "NetFlow",
    "NetworkMonitoring",
    "ServiceMap",
    "Updates",
    "VMInsights",
    "WindowsDefenderATP",
    "WindowsFirewall",
    "WinLog"
)

# Ensure only the selected intelligence packs are enabled
$packsAvailable = Get-AzOperationalInsightsIntelligencePack -ResourceGroupName $workspace.ResourceGroupName -WorkspaceName $workspace.Name
foreach ($pack in $packsAvailable) {
    if ($pack.Name -in $packNames) {
        if ($pack.Enabled) {
            Add-LogMessage -Level InfoSuccess "'$($pack.Name)' Intelligence Pack already enabled."
        } else {
            $null = Set-AzOperationalInsightsIntelligencePack -IntelligencePackName $pack.Name -WorkspaceName $workspace.Name -ResourceGroupName $workspace.ResourceGroupName -Enabled $true
            if ($?) {
                Add-LogMessage -Level Success "'$($pack.Name)' Intelligence Pack enabled."
            } else {
                Add-LogMessage -Level Fatal "Failed to enable '$($pack.Name)' Intelligence Pack!"
            }
        }
    } else {
        if ($pack.Enabled) {
            $null = Set-AzOperationalInsightsIntelligencePack -IntelligencePackName $pack.Name -WorkspaceName $workspace.Name -ResourceGroupName $workspace.ResourceGroupName -Enabled $false
            if ($?) {
                Add-LogMessage -Level Success "'$($pack.Name)' Intelligence Pack disabled."
            } else {
                Add-LogMessage -Level Fatal "Failed to disable '$($pack.Name)' Intelligence Pack!"
            }
        } else {
            Add-LogMessage -Level InfoSuccess "'$($pack.Name)' Intelligence Pack already disabled."
        }
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
