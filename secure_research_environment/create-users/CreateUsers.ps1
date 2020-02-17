Param (
     [Parameter(Mandatory=$true, 
          HelpMessage="Path to the CSV file of users")]
     [ValidateNotNullOrEmpty()]
     [string]$userFilePath
)

$domain=(Get-ADForest).Domains
$userOuPath=(Get-ADObject -Filter * | Where-Object { $_.Name -eq "Safe Haven Research Users"}).DistinguishedName

Add-Type -AssemblyName System.Web
$Description = "Research User"

Import-Csv $userFilePath | foreach-object {
Write-Host $_

$UserPrincipalName = $_.SamAccountName + "@" + "$domain"
Write-Host "UserPrincipalName = " $UserPrincipalName
$password = [System.Web.Security.Membership]::GeneratePassword(12,3)
$props = @{
    SamAccountName = $_.SamAccountName
    UserPrincipalName = $UserPrincipalName
    Name = "$($_.GivenName) $($_.Surname)"
    DisplayName = "$($_.GivenName) $($_.Surname)"
    GivenName = $_.GivenName
    SurName = $_.Surname
    Department = $Department
    Description = $Description
    Path = "$userOuPath"
    Enabled = $True
    AccountPassword = (ConvertTo-SecureString $Password -AsPlainText -force)
    PasswordNeverExpires = $False
    Mobile = $_.Mobile
    Email = $UserPrincipalName
    Country = "GB"
}

Write-Host @props

New-ADUser @props -PassThru
}

# Force sync with AzureAD. It will still take around 5 minutes for changes to propagate
Import-Module –Name "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync"
Start-ADSyncSyncCycle -PolicyType Delta
