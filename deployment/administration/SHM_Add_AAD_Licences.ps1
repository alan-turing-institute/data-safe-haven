param(
  [Parameter(Mandatory = $false, HelpMessage = "SKU for the licence you want to assign")]
  [string]$licenceSku = "AAD_PREMIUM",
  [Parameter(Mandatory = $true, HelpMessage = "Azure Active Directory tenant ID")]
  [string]$tenantId
)

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


# Connect to Microsoft Graph
# --------------------------
if (Get-MgContext) { Disconnect-MgGraph } # force a refresh of the Microsoft Graph token before starting
Add-LogMessage -Level Info "Attempting to authenticate with Microsoft Graph"
Connect-MgGraph -TenantId $tenantId -Scopes "Directory.ReadWrite.All" -ErrorAction Stop
if (Get-MgContext) {
    Add-LogMessage -Level Success "Authenticated with Microsoft Graph"
} else {
    Add-LogMessage -Level Fatal "Failed to authenticate with Microsoft Graph"
}

# Get the appropriate licence
$LicenceSkuId = (Get-MgSubscribedSku | Where-Object -Property SkuPartNumber -Value $licenceSku -EQ).SkuId
Add-LogMessage -Level Info "Preparing to add licence '$licenceSku' ($($Licence.SkuId)) to unlicenced users"

# Find all users without assigned licences who have an OnPremisesSecurityIdentifier (indicating that they were synched from a local AD)
$unlicensedUsers = Get-MgUser | Where-Object { -Not $_.AssignedLicenses } | Where-Object { $_.OnPremisesSecurityIdentifier }
Add-LogMessage -Level Info "Assigning licences to $($unlicensedUsers.Count) unlicenced users"
$unlicensedUsers | ForEach-Object { Set-MgUserLicense -UserId $_.Id -AddLicenses @{SkuId = $LicenceSkuId } -RemoveLicenses @() }
