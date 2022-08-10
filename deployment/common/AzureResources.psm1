Import-Module Az.Resources -ErrorAction Stop


# Get the resource ID for a named resource
# ----------------------------------------
function Get-ResourceId {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Resource to obtain ID for")]
        [System.Object]$ResourceName
    )
    return Get-AzResource | Where-Object { $_.Name -eq $ResourceName } | ForEach-Object { $_.ResourceId } | Select-Object -First 1
}
Export-ModuleMember -Function Get-ResourceId


# Get the resource ID for a named resource
# ----------------------------------------
function Get-ResourceGroupName {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Resource to obtain ID for")]
        [System.Object]$ResourceName
    )
    return Get-AzResource | Where-Object { $_.Name -eq $ResourceName } | ForEach-Object { $_.ResourceGroupName } | Select-Object -First 1
}
Export-ModuleMember -Function Get-ResourceGroupName
