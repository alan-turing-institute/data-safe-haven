param(
  [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID")]
  [string]$shmId,
  [Parameter(Mandatory = $false,HelpMessage = "Sku for the licence you want to assign")]
  [string]$licenceSku = "AAD_PREMIUM"
)

Import-Module AzureAD.Standard.Preview
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force

$config = Get-ShmFullConfig $shmId
$shmDomain = $config.domain.fqdn

# Connect to the Azure AD
# We connect within the script to ensure we are connected to the right Azure AD for the SHM
Add-LogMessage -Level Info "Connecting to Azure AD for '$shmDomain'..."
$_ = Connect-AzureAD -TenantId $shmDomain


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

# Disconnect from AzureAD
# We disconnect from the SHM Azure AD to ensure the user does not assume they are still 
# connected to a different Azure AD they may have been connected to prior to running this
# script and therefore perform subsequent operations against the wrong Azure AD
Add-LogMessage -Level Info "Disconnecting from AzureAD for '$shmDomain"
Disconnect-AzureAD