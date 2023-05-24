Import-Module Az.Monitor -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Create an Azure Monitor Private Link Scope
# ------------------------------------------
function Deploy-MonitorPrivateLinkScope {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of private link scope to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Ensuring that private link scope '$Name' exists..."
    $link = Get-AzInsightsPrivateLinkScope -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating private link scope '$Name'"
        $link = New-AzInsightsPrivateLinkScope -Location "Global" -ResourceGroupName $ResourceGroupName -Name $Name
        if ($?) {
            Add-LogMessage -Level Success "Created private link scope '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create private link scope '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Private link scope '$Name' already exists"
    }
    return $link
}
Export-ModuleMember -Function Deploy-MonitorPrivateLinkScope


# Connect a log workspace to a private link
# -----------------------------------------
function Connect-PrivateLinkToLogWorkspace {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Log analytics workspace to connect")]
        [Microsoft.Azure.Management.Internal.Network.Common.IOperationalInsightWorkspace]$LogAnalyticsWorkspace,
        [Parameter(Mandatory = $true, HelpMessage = "Name of private link scope to deploy")]
        [Microsoft.Azure.Commands.Insights.OutputClasses.PSMonitorPrivateLinkScope]$PrivateLinkScope
    )
    Add-LogMessage -Level Info "Ensuring that log analytics workspace '$($LogAnalyticsWorkspace.Name)' is connected to private link '$($PrivateLinkScope.Name)'..."
    $ResourceGroupName = (Get-AzResource | Where-Object { $_.Name -eq $PrivateLinkScope.Name }).ResourceGroupName
    $resource = Get-AzInsightsPrivateLinkScopedResource -ScopeName $PrivateLinkScope.Name -ResourceGroupName $ResourceGroupName | Where-Object { $_.LinkedResourceId -eq $LogAnalyticsWorkspace.ResourceId } #| Select-Object -First 1 -ErrorAction Stop
    if ($resource.Count -gt 1) { $resource = $resource[0] } # Note. Select-Object on the previous command causes a PipelineStoppedException
    if (-not $resource) {
        Add-LogMessage -Level Info "[ ] Connecting log analytics workspace '$($LogAnalyticsWorkspace.Name)' to private link '$($PrivateLinkScope.Name)'"
        $resource = New-AzInsightsPrivateLinkScopedResource -LinkedResourceId $LogAnalyticsWorkspace.ResourceId -ResourceGroupName $ResourceGroupName -ScopeName $PrivateLinkScope.Name -Name "scoped-link-$($LogAnalyticsWorkspace.Name)"
        if ($?) {
            Add-LogMessage -Level Success "Connected log analytics workspace '$($LogAnalyticsWorkspace.Name)' to private link '$($PrivateLinkScope.Name)'"
        } else {
            Add-LogMessage -Level Fatal "Failed to connect log analytics workspace '$($LogAnalyticsWorkspace.Name)' to private link '$($PrivateLinkScope.Name)'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Log analytics workspace '$($LogAnalyticsWorkspace.Name)' is already connected to private link '$($PrivateLinkScope.Name)'"
    }
    return $resource
}
Export-ModuleMember -Function Connect-PrivateLinkToLogWorkspace


# Connect resource to logging workspace
# -------------------------------------
function Set-LogAnalyticsDiagnostics {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Resource to set diagnostics on")]
        [string]$ResourceId,
        [Parameter(Mandatory = $true, HelpMessage = "Log analytics workspace to connect")]
        [string]$ResourceName,
        [Parameter(Mandatory = $true, HelpMessage = "Log analytics workspace to store the diagnostics")]
        [string]$WorkspaceId
    )
    Add-LogMessage -Level Info "Enable logging for $ResourceName to log analytics workspace"
    $null = New-AzDiagnosticSetting -Name "LogToWorkspace" -ResourceId $ResourceId -WorkspaceId $WorkspaceId
    if ($?) {
        Add-LogMessage -Level Success "Enabled logging for $ResourceName to log analytics workspace"
    } else {
        Add-LogMessage -Level Fatal "Failed to enable logging for $ResourceName to log analytics workspace!"
    }
}
Export-ModuleMember -Function Set-LogAnalyticsDiagnostics
