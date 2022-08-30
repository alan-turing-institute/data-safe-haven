param(
  [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId,
  [Parameter(Mandatory = $false, HelpMessage = "SKU for the licence you want to assign")]
  [string]$licenceSku = "AAD_PREMIUM"
)

Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


# Get config
# ----------
$config = Get-ShmConfig -shmId $shmId


# Connect to Microsoft Graph
# --------------------------
if (-not (Get-MgContext)) {
  Add-LogMessage -Level Info "Attempting to authenticate with Microsoft Graph. Please sign in with an account with admin rights over the Azure Active Directory you plan to use."
  Connect-MgGraph -TenantId $config.azureAdTenantId -Scopes "Directory.ReadWrite.All" -ErrorAction Stop
}
if (Get-MgContext) {
    Add-LogMessage -Level Success "Authenticated with Microsoft Graph"
} else {
    Add-LogMessage -Level Fatal "Failed to authenticate with Microsoft Graph"
}


# Get the appropriate licence
# ---------------------------
$LicenceSkuId = (Get-MgSubscribedSku | Where-Object -Property SkuPartNumber -Value $licenceSku -EQ).SkuId
Add-LogMessage -Level Info "Preparing to add licence '$licenceSku' ($($Licence.SkuId)) to unlicenced users"


# Find all users without assigned licences who have an OnPremisesSecurityIdentifier.
# This indicates that they originated from a local AD.
# ----------------------------------------------------------------------------------
$unlicensedUsers = Get-MgUser | Where-Object { -Not $_.AssignedLicenses } | Where-Object { $_.OnPremisesSecurityIdentifier }
Add-LogMessage -Level Info "Assigning licences to $($unlicensedUsers.Count) unlicenced users"
$unlicensedUsers | ForEach-Object { Set-MgUserLicense -UserId $_.Id -AddLicenses @{SkuId = $LicenceSkuId } -RemoveLicenses @() }
