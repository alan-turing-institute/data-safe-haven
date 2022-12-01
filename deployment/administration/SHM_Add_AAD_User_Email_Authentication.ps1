param(
  [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
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

# Find all users without with OnPremisesSyncEnabled=True, with Mail entries, who have not already got an authenticationemailmethod.
# This indicates that they originated from a local AD.
# ----------------------------------------------------------------------------------
$users = Get-MgUser -Property Mail, OnPremisesSyncEnabled, UserPrincipalName | where { $_.OnPremisesSyncEnabled } | where { $_.Mail }
$users | ForEach-Object { 
    if (Get-MgUserAuthenticationEmailMethod -UserId $_.UserPrincipalName ) {
        Add-LogMessage -Level Info "User '$($_.UserPrincipalName)' already has an authentication email"
    } else {
        Add-LogMessage -Level Info "Adding authentication email '$($_.Mail)' to user '$($_.UserPrincipalName)'"
        $null = New-MgUserAuthenticationEmailMethod -UserId $_.UserPrincipalName -EmailAddress $_.Mail
    }
}
