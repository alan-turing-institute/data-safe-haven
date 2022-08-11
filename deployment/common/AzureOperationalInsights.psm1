Import-Module Az.OperationalInsights -ErrorAction Stop
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Create log analytics workspace if it does not exist
# ---------------------------------------------------
function Deploy-LogAnalyticsWorkspace {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of log analytics workspace to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location to deploy into")]
        [string]$Location
    )
    Add-LogMessage -Level Info "Ensuring that log analytics workspace '$Name' exists..."
    $Workspace = Get-AzOperationalInsightsWorkspace -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating log analytics workspace '$Name'"
        $Workspace = New-AzOperationalInsightsWorkspace -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -Sku pergb2018
        if ($?) {
            Add-LogMessage -Level Success "Created log analytics workspace '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create log analytics workspace '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Log analytics workspace '$Name' already exists"
    }
    if (-not $(Get-AzResourceProvider | Where-Object { $_.ProviderNamespace -eq "Microsoft.Insights" })) {
        Add-LogMessage -Level Info "[ ] Registering Microsoft.Insights provider in this subscription..."
        $null = Register-AzResourceProvider -ProviderNamespace "Microsoft.Insights"
        Wait-For -Target "Microsoft.Insights provider to register" -Seconds 300
        if ($(Get-AzResourceProvider | Where-Object { $_.ProviderNamespace -eq "Microsoft.Insights" })) {
            Add-LogMessage -Level Success "Successfully registered Microsoft.Insights provider"
        } else {
            Add-LogMessage -Level Fatal "Failed to register Microsoft.Insights provider!"
        }
    }
    return $Workspace
}
Export-ModuleMember -Function Deploy-LogAnalyticsWorkspace
