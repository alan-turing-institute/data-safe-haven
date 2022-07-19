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
                                                       -ResourceGroupName $LogAnalyticsWorkspaceResourceGroupName `
                                                       -WorkspaceName $LogAnalyticsWorkspaceName `
                                                       -WriteAccessResourceId "$accountResourceId"
        if ($?) {
            Add-LogMessage -Level Success "Linked automation account '$AutomationAccountName' to log analytics workspace '$LogAnalyticsWorkspaceName'."
        } else {
            Add-LogMessage -Level Fatal "Failed to link automation account '$AutomationAccountName' to log analytics workspace '$LogAnalyticsWorkspaceName'!"
        }
    } else {
        Add-LogMessage -Level Info "Automation account '$AutomationAccountName' is already linked to log analytics workspace '$LogAnalyticsWorkspaceName'."
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
    # As New-AzMonitorLogAnalyticsSolution always fails, we attempt to create and then check for existence
    $null = New-AzMonitorLogAnalyticsSolution -ResourceGroupName $Workspace.ResourceGroupName -Type "$SolutionType" -WorkspaceResourceId $Workspace.ResourceId -Location $Workspace.Location -ErrorAction SilentlyContinue
    $solution = Get-AzMonitorLogAnalyticsSolution -ResourceGroupName $Workspace.ResourceGroupName | Where-Object { $_.Name -eq "$SolutionType($($Workspace.Name))" }
    if ($solution) {
        Add-LogMessage -Level Success "Deployed solution '$SolutionType' to $($Workspace.Name)"
    } else {
        Add-LogMessage -Level Fatal "Failed to deploy solution '$SolutionType' to $($Workspace.Name)!"
    }
    return $solution
}
Export-ModuleMember -Function Deploy-LogAnalyticsSolution
