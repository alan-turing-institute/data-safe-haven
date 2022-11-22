param (
    [Parameter(Mandatory = $false, HelpMessage = "User details as base64-encoded string")]
    [ValidateNotNullOrEmpty()]
    [string]$UserDetailsB64
)

function GeneratePassword ([int] $PasswordLength) {
    Add-Type -AssemblyName "System.Web"
    $PassComplexityCheck = $false
    while (-not $PassComplexityCheck) {
        $GeneratedPassword = [System.Web.Security.Membership]::GeneratePassword($PasswordLength, [int]($PasswordLength / 3))
        if (($GeneratedPassword -cmatch "[A-Z]") -and
            ($GeneratedPassword -cmatch "[a-z]") -and
            ($GeneratedPassword -match "[\d]") -and
            ($GeneratedPassword -match "[\W]")) {
            $PassComplexityCheck = $True
        }
    }
    return $GeneratedPassword
}

# Write user details to a local file
$UserFilePath = "C:\DataSafeHaven\ActiveDirectory\users.csv"
$UserDetails = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($UserDetailsB64))
$UserDetails | Out-File $UserFilePath

# Get common properties
$Domain = (Get-ADForest -Current LocalComputer).Domains
$UserOuPath = (Get-ADObject -Filter * | Where-Object { $_.Name -eq "Data Safe Haven Research Users" }).DistinguishedName

# Create users if they do not exist
Import-Csv -Path $UserFilePath -Delimiter ";" | ForEach-Object {
    $DisplayName = "$($_.GivenName) $($_.Surname)"
    $UserPrincipalName = "$($_.SamAccountName)@${Domain}"
    # Attempt to create user if they do not exist
    try {
        New-ADUser -AccountPassword $(ConvertTo-SecureString $(GeneratePassword(12)) -AsPlainText -Force) `
                   -Country $_.Country `
                   -Department "Data Safe Haven" `
                   -Description "Research User" `
                   -DisplayName "$DisplayName" `
                   -Email $_.Email `
                   -Enabled $True `
                   -GivenName $_.GivenName `
                   -Mobile $_.Mobile `
                   -Name "$DisplayName" `
                   -PasswordNeverExpires $False `
                   -Path "$UserOuPath" `
                   -SurName $_.Surname `
                   -UserPrincipalName $UserPrincipalName `
                   -SamAccountName $_.SamAccountName `
                   -ErrorAction Stop
        Write-Output "INFO: Created a user with name '<fg=green>$UserPrincipalName</>'"
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException] {
        Write-Output "WARNING: User with name '<fg=green>$UserPrincipalName</>' already exists"
    } catch {
        Write-Output "ERROR: Failed to create user with name '<fg=green>$UserPrincipalName</>'!"
        Write-Output "ERROR: Cause of error: $($_.Exception)"
    }
}
Remove-Item $UserFilePath

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
