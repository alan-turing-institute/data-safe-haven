param (
    [Parameter(Mandatory = $false, HelpMessage = "User list as base64-encoded string")]
    [ValidateNotNullOrEmpty()]
    [string]$UserListB64
)

# Construct list of users to remove
$UserList = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($UserListB64)).Split()

# Find users in the OU path and remove them
$UserOuPath = (Get-ADObject -Filter * | Where-Object { $_.Name -eq "Data Safe Haven Research Users" }).DistinguishedName
$UserList | ForEach-Object {
    $user = Get-ADUser -Filter "SamAccountName -eq '$_'" -SearchBase $UserOuPath
    Write-Output "INFO: Removing user $($user.SamAccountName)"
    Remove-ADUser -Identity $user
}

# Force sync with AzureAD. It will still take around 5 minutes for changes to propagate
Write-Output "INFO: Synchronising local Active Directory with Azure"
try {
    Import-Module -Name "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync" -ErrorAction Stop
    Start-ADSyncSyncCycle -PolicyType Delta | Out-Null
    Write-Output "INFO: Finished synchronising local Active Directory with Azure"
} catch [System.IO.FileNotFoundException] {
    Write-Output "WARNING: Skipping as Azure AD Sync is not installed"
} catch {
    Write-Output "ERROR: Unable to run Azure Active Directory synchronisation!"
    Write-Output "ERROR: Cause of error: $($_.Exception)"
}
