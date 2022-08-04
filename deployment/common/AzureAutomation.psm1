Import-Module Az.Automation -ErrorAction Stop
Import-Module Az.MonitoringSolutions -ErrorAction Stop


# Connect an automation account to a log analytics workspace
# ----------------------------------------------------------
function Connect-AutomationAccountLogAnalytics {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of automation account to connect")]
        [string]$AutomationAccountName,
        [Parameter(Mandatory = $true, HelpMessage = "Log analytics workspace to connect")]
        [Microsoft.Azure.Management.Internal.Network.Common.IOperationalInsightWorkspace]$LogAnalyticsWorkspace
    )
    $accountResourceId = (Get-AzResource | Where-Object { $_.Name -eq $AutomationAccountName } | Select-Object -First 1).ResourceId
    $linked = Get-AzOperationalInsightsLinkedService -ResourceGroupName $LogAnalyticsWorkspace.ResourceGroupName -WorkspaceName $LogAnalyticsWorkspace.Name | Where-Object { ($_.Name -eq "Automation") -and ($_.ResourceId -eq $accountResourceId) }
    if (-not $linked) {
        $null = Set-AzOperationalInsightsLinkedService -LinkedServiceName "Automation" `
                                                       -ResourceGroupName $LogAnalyticsWorkspace.ResourceGroupName `
                                                       -WorkspaceName $LogAnalyticsWorkspace.Name `
                                                       -WriteAccessResourceId "$accountResourceId"
        if ($?) {
            Add-LogMessage -Level Success "Linked automation account '$AutomationAccountName' to log analytics workspace '$($LogAnalyticsWorkspace.Name)'."
        } else {
            Add-LogMessage -Level Fatal "Failed to link automation account '$AutomationAccountName' to log analytics workspace '$($LogAnalyticsWorkspace.Name)'!"
        }
    } else {
        Add-LogMessage -Level Info "Automation account '$AutomationAccountName' is already linked to log analytics workspace '$($LogAnalyticsWorkspace.Name)'."
    }
}
Export-ModuleMember -Function Connect-AutomationAccountLogAnalytics


# Create automation account if it does not exist
# ----------------------------------------------
function Deploy-AutomationAccount {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Location of automation account to deploy")]
        [string]$Location,
        [Parameter(Mandatory = $true, HelpMessage = "Name of automation account to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Ensuring that automation account '$Name' exists..."
    try {
        $automationAccount = Get-AzAutomationAccount -Name $Name -ResourceGroupName $ResourceGroupName -ErrorAction Stop
        Add-LogMessage -Level InfoSuccess "Automation account '$Name' already exists"
    } catch {
        Add-LogMessage -Level Info "[ ] Creating automation account '$Name'"
        $automationAccount = New-AzAutomationAccount -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -Plan "Free"
        if ($?) {
            Add-LogMessage -Level Success "Created automation account '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create automation account '$Name'!"
        }
    }
    return $automationAccount
}
Export-ModuleMember -Function Deploy-AutomationAccount


# Create automation query if it does not exist
# --------------------------------------------
function Deploy-AutomationAzureQuery {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Automation account to deploy the schedule into")]
        [Microsoft.Azure.Commands.Automation.Model.AutomationAccount]$Account,
        [Parameter(Mandatory = $true, HelpMessage = "Resource groups covered by the query")]
        [Microsoft.Azure.Commands.ResourceManager.Cmdlets.SdkModels.PSResourceGroup[]]$ResourceGroups
    )
    try {
        return New-AzAutomationUpdateManagementAzureQuery -AutomationAccountName $Account.AutomationAccountName `
                                                          -Location $Account.location `
                                                          -ResourceGroupName $Account.ResourceGroupName `
                                                          -Scope @($ResourceGroups | ForEach-Object { $_.ResourceId } ) `
                                                          -ErrorAction Stop
    } catch {
        Add-LogMessage -Level Fatal "Failed to create automation query!" -Exception $_.Exception
    }
}
Export-ModuleMember -Function Deploy-AutomationAzureQuery


# Create automation schedule if it does not exist
# -----------------------------------------------
function Deploy-AutomationScheduleDaily {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Automation account to deploy the schedule into")]
        [Microsoft.Azure.Commands.Automation.Model.AutomationAccount]$Account,
        [Parameter(Mandatory = $false, HelpMessage = "Interval in days")]
        [string]$DayInterval = 1,
        [Parameter(Mandatory = $true, HelpMessage = "Name of automation schedule to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Start time")]
        [string]$Time,
        [Parameter(Mandatory = $false, HelpMessage = "Time zone")]
        [System.TimeZoneInfo]$TimeZone = "UTC"
    )
    try {
        Add-LogMessage -Level Info "Ensuring that automation schedule '$Name' exists..."
        # Remove any existing automation schedule with the same name, noting that a UUID might have been appended to the name
        $schedule = Get-AzAutomationSchedule -ResourceGroupName $Account.ResourceGroupName -AutomationAccountName $Account.AutomationAccountName | Where-Object { $_.Name -like "${Name}*" } | Remove-AzAutomationSchedule -Force
        # Create the new automation schedule
        Add-LogMessage -Level Info "[ ] Creating automation schedule '$Name'"
        $startTime = (Get-Date $Time).AddDays(1)
        $schedule = New-AzAutomationSchedule -AutomationAccountName $account.AutomationAccountName `
                                             -DayInterval $DayInterval `
                                             -ForUpdateConfiguration `
                                             -Name $Name `
                                             -ResourceGroupName $account.ResourceGroupName `
                                             -StartTime $startTime `
                                             -TimeZone $TimeZone.Id `
                                             -ErrorAction Stop
        Add-LogMessage -Level Success "Created automation schedule '$($schedule.Name)'"
        return $schedule
    } catch {
        Add-LogMessage -Level Fatal "Failed to create automation schedule '$Name'!" -Exception $_.Exception
    }
}
Export-ModuleMember -Function Deploy-AutomationScheduleDaily


# Create log analytics solution if it does not exist
# --------------------------------------------------
function Deploy-LogAnalyticsSolution {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Solution type")]
        [ValidateSet("Updates")]
        [string]$SolutionType,
        [Parameter(Mandatory = $true, HelpMessage = "Log analytics workspace")]
        [Microsoft.Azure.Management.Internal.Network.Common.IOperationalInsightWorkspace]$Workspace
    )
    $solution = Get-AzMonitorLogAnalyticsSolution -ResourceGroupName $Workspace.ResourceGroupName | Where-Object { $_.Name -eq "$SolutionType($($Workspace.Name))" }
    if (-not $solution) {
        # As New-AzMonitorLogAnalyticsSolution always fails, we attempt to create and then check for existence
        $null = New-AzMonitorLogAnalyticsSolution -ResourceGroupName $Workspace.ResourceGroupName -Type "$SolutionType" -WorkspaceResourceId $Workspace.ResourceId -Location $Workspace.Location -ErrorAction SilentlyContinue
        $solution = Get-AzMonitorLogAnalyticsSolution -ResourceGroupName $Workspace.ResourceGroupName | Where-Object { $_.Name -eq "$SolutionType($($Workspace.Name))" }
        if ($solution) {
            Add-LogMessage -Level Success "Deployed solution '$SolutionType' to $($Workspace.Name)"
        } else {
            Add-LogMessage -Level Fatal "Failed to deploy solution '$SolutionType' to $($Workspace.Name)!"
        }
    } else {
        Add-LogMessage -Level Info "Solution '$SolutionType' has already been deployed to $($Workspace.Name)"
    }
    return $solution
}
Export-ModuleMember -Function Deploy-LogAnalyticsSolution


# Register VMs with automation schedule
# -------------------------------------
function Register-VmsWithAutomationSchedule {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Automation account to use")]
        [Microsoft.Azure.Commands.Automation.Model.AutomationAccount]$Account,
        [Parameter(Mandatory = $false, HelpMessage = "How many hours to allow for updates")]
        [int]$DurationHours = 2,
        [Parameter(Mandatory = $true, ParameterSetName = "ByQuery", HelpMessage = "Azure query to apply the schedule to")]
        [Microsoft.Azure.Commands.Automation.Model.UpdateManagement.AzureQueryProperties]$Query,
        [Parameter(Mandatory = $true, HelpMessage = "Schedule to apply to the VMs")]
        [Microsoft.Azure.Commands.Automation.Model.Schedule]$Schedule,
        [Parameter(Mandatory = $true, ParameterSetName = "ByVMId", HelpMessage = "IDs of VMs to apply the schedule to")]
        [AllowNull()]
        [string[]]$VmIds,
        [Parameter(Mandatory = $true, HelpMessage = "Type of VMs")]
        [ValidateSet("Linux", "Windows")]
        [string]$VmType
    )
    # Use either query or VM IDs
    $params = @{ "Duration" = (New-TimeSpan -Hours $DurationHours) }
    if ($Query) {
        $params["AzureQuery"] = $Query
    } else {
        if ((-not $VmIds) -or ($VmIds.Count -eq 0)) {
            Add-LogMessage -Level Warning "Skipping application of automation schedule '$($ScheduleName)' as no VMs were specified."
            return $null
        }
        $params["AzureVMResourceId"] = $VmIds
    }
    Add-LogMessage -Level Info "Applying automation schedule '$($Schedule.Name)' for $VmType VM(s)..."
    try {
        # Remove any existing update configuration with the same name
        $null = Remove-AzAutomationSoftwareUpdateConfiguration -ResourceGroupName "$($Account.ResourceGroupName)" -AutomationAccountName "$($Account.AutomationAccountName)" -Name $Schedule.Name -ErrorAction SilentlyContinue
        if ($VmType -eq "Windows") {
            $config = New-AzAutomationSoftwareUpdateConfiguration -AutomationAccountName $Account.AutomationAccountName `
                                                                  -Confirm:$false `
                                                                  -ErrorAction Stop `
                                                                  -IncludedUpdateClassification @("Unclassified", "Critical", "Security", "UpdateRollup", "FeaturePack", "ServicePack", "Definition", "Tools", "Updates") `
                                                                  -ResourceGroupName $Account.ResourceGroupName `
                                                                  -Schedule $Schedule `
                                                                  -Windows `
                                                                  @params
        } else {
            $config = New-AzAutomationSoftwareUpdateConfiguration -AutomationAccountName $Account.AutomationAccountName `
                                                                  -Confirm:$false `
                                                                  -ErrorAction Stop `
                                                                  -IncludedPackageClassification @("Unclassified", "Critical", "Security", "Other") `
                                                                  -Linux `
                                                                  -ResourceGroupName $Account.ResourceGroupName `
                                                                  -Schedule $Schedule `
                                                                  @params
        }
        Add-LogMessage -Level Success "Applied automation schedule '$($Schedule.Name)' to $VmType VM(s)."
        return $config
    } catch {
        Add-LogMessage -Level Fatal "Failed to apply automation schedule '$($Schedule.Name)' to $($VmIds.Count) VM(s)!" -Exception $_.Exception
    }
}
Export-ModuleMember -Function Register-VmsWithAutomationSchedule
