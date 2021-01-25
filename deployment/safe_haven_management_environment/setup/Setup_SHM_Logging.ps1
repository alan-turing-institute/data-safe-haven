param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Create logging resource group if it does not exist
# --------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.logging.rg -Location $config.location


# Get Log Analytics Workspace details
# -----------------------------------
$workspace = Get-AzOperationalInsightsWorkspace -Name $config.logging.workspaceName -ResourceGroup $config.logging.rg
$key = Get-AzOperationalInsightsWorkspaceSharedKey -Name $config.logging.workspaceName -ResourceGroup $config.logging.rg


# Enable the collection of syslog logs from Linux hosts
# -----------------------------------------------------
# Syslog facilities:
#   See
#     - https://wiki.gentoo.org/wiki/Rsyslog#Facility
#     - https://tools.ietf.org/html/rfc5424 (page 10)
#     - https://rsyslog.readthedocs.io/en/latest/configuration/filters.html
#
#   kern:     kernel messages
#   user:     user: level messages
#   mail:     mail system
#   daemon:   system daemons
#   auth:     security/authorization messages
#   syslog:   messages generated internally by syslogd
#   lpr:      line printer subsystem
#   news:     network news subsystem
#   uucp:     UUCP subsystem
#   cron:     clock daemon
#   security: security/authorization messages (the same as auth, not used)
#   ftp:      FTP daemon
#   ntp:      NTP subsystem
#   logaudit: log audit
#   logalert: log alert
#   clock:    clock daemon
#   local0:   local use 0
#   local1:   local use 1
#   local2:   local use 2
#   local3:   local use 3
#   local4:   local use 4
#   local5:   local use 5
#   local6:   local use 6
#   local7:   local use 7
$facilityNames = @(
    "kern",
    "user",
    "mail",
    "daemon",
    "auth",
    "syslog",
    "lpr",
    "news",
    "uucp",
    "cron",
    "authpriv",
    "ftp",
    "ntp",
    "logaudit",
    "logalert",
    "clock",
    "local0",
    "local1",
    "local2",
    "local3",
    "local4",
    "local5",
    "local6",
    "local7"
)
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
foreach ($facilityName in $facilityNames) {
    $null = New-AzOperationalInsightsLinuxSyslogDataSource `
    -ResourceGroupName $config.logging.rg `
    -WorkspaceName $config.logging.workspaceName `
    -Name "Linux-syslog-$($facilityName)" `
    -Facility $facilityName `
    -CollectEmergency `
    -CollectAlert `
    -CollectCritical `
    -CollectError `
    -CollectWarning `
    -CollectNotice `
    -CollectInformational `
    -CollectDebug

    if ($?) {
        Add-LogMessage -Level Success "Logging activated for '$facilityName' syslog facility."
    } else {
        Add-LogMessage -Level Fatal "Failed to activate logging for '$facilityName' syslog facility!"
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

foreach ($eventLogName in $eventLogNames) {
    $sourceName = "windows-event-$eventLogName".Replace("%", "percent").Replace("/", "-per-").Replace(" ", "-").ToLower()
    $source = Get-AzOperationalInsightsDataSource -Name $sourceName `
                                                  -ResourceGroupName $config.logging.rg `
                                                  -WorkspaceName $config.logging.workspaceName
    if ($source) {
        Add-LogMessage -Level InfoSuccess "Logging already active for '$eventLogName'."
    } else {
        $null = New-AzOperationalInsightsWindowsEventDataSource -Name $sourceName `
                                                                -ResourceGroupName $config.logging.rg `
                                                                -WorkspaceName $config.logging.workspaceName `
                                                                -EventLogName $eventLogName `
                                                                -CollectErrors `
                                                                -CollectWarnings `
                                                                -CollectInformation
        if ($?) {
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
foreach ($counter in $counters) {
    $sourceName = "windows-counter-$($counter.setName)-$($counter.counterName)".Replace("%", "percent").Replace("/", "-per-").Replace(" ", "-").ToLower()
    $source = Get-AzOperationalInsightsDataSource -Name $sourceName `
                                                  -ResourceGroupName $config.logging.rg `
                                                  -WorkspaceName $config.logging.workspaceName
    if ($source) {
        Add-LogMessage -Level InfoSuccess "Logging already active for '$($counter.setName)/$($counter.counterName)'"
    } else {
        $null = New-AzOperationalInsightsWindowsPerformanceCounterDataSource -Name $sourceName `
                                                                             -ResourceGroupName $config.logging.rg `
                                                                             -WorkspaceName $config.logging.workspaceName `
                                                                             -ObjectName $counter.setName `
                                                                             -InstanceName "*" `
                                                                             -CounterName $counter.counterName `
                                                                             -IntervalSeconds 60
        if ($?) {
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
    "AgentHealthAssessment",
    "AzureActivity",
    "AzureNetworking",
    "AntiMalware",
    "CapacityPerformance",
    "ChangeTracking",
    "DnsAnalytics",
    "InternalWindowsEvent",
    "NetFlow",
    "NetworkMonitoring",
    "ServiceMap",
    "Updates",
    "VMInsights",
    "WindowsDefenderATP",
    "WindowsFirewall",
    "WinLog"
)
foreach ($packName in $packNames) {
    $pack = Get-AzOperationalInsightsIntelligencePack -WorkspaceName $config.logging.workspaceName -ResourceGroupName $config.logging.rg | Where-Object { $_.Name -eq $packName }
    if ($pack.Enabled) {
        Add-LogMessage -Level InfoSuccess "'$packName' Intelligence Pack already enabled."
    } else {
        $pack = Set-AzOperationalInsightsIntelligencePack -IntelligencePackName $packName `
                                                          -WorkspaceName $config.logging.workspaceName `
                                                          -ResourceGroupName $config.logging.rg `
                                                          -Enabled $true
        if ($?) {
            Add-LogMessage -Level Success "'$packName' Intelligence Pack enabled."
        } else {
            Add-LogMessage -Level Fatal "Failed to enable '$packName' Intelligence Pack!"
        }
    }
}


# Ensure logging is active on all SHM VMs
# ---------------------------------------
$rgFilter = "RG_SHM_$($config.id)*"
$shmResourceGroups = @(Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like $rgFilter } | Where-Object { $_.ResourceGroupName -notlike "*WEBAPP*" })
foreach ($shmResourceGroup in $shmResourceGroups) {
    foreach ($vm in $(Get-AzVM -ResourceGroup $shmResourceGroup.ResourceGroupName)) {
        $null = Deploy-VirtualMachineMonitoringExtension -vm $vm -workspaceId $workspace.CustomerId -WorkspaceKey $key.PrimarySharedKey
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
