param(
  [Parameter(Mandatory = $true,HelpMessage = "Enter tenant ID for the relevant Azure Active Directory")]
  [string]$tenantId,
  [Parameter(Mandatory = $false,HelpMessage = "Sku for the licence you want to assign")]
  [string]$licenceSku = "AAD_PREMIUM"
)

Import-Module AzureAD.Standard.Preview
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force

# Connect to the Azure AD
$_ = Connect-AzureAD -TenantId $tenantId


# Get the appropriate licence
$Licence = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicense
$Licence.SkuId = (Get-AzureADSubscribedSku | Where-Object -Property SkuPartNumber -Value $licenceSku -EQ).SkuID
$LicencesToAssign = New-Object -TypeName Microsoft.Open.AzureAD.Model.AssignedLicenses
$LicencesToAssign.AddLicenses = $Licence
Add-LogMessage -Level Info "Preparing to add licence '$licenceSku' ($($Licence.SkuId)) to unlicenced users"


# Find all users without assigned licences who have an OnPremisesSecurityIdentifier (indicating that they were synched from a local AD)
$unlicensedUsers = Get-AzureAdUser | Where-Object { -Not $_.AssignedLicenses } | Where-Object { $_.OnPremisesSecurityIdentifier }
Add-LogMessage -Level Info "Assigning licences to $($unlicensedUsers.Count) unlicenced users"
$unlicensedUsers | Set-AzureADUserLicense -AssignedLicenses $LicencesToAssign
