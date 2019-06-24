Param (
     [Parameter(Mandatory=$true, 
          HelpMessage="Path to the CSV file of users")]
     [ValidateNotNullOrEmpty()]
     [string]$userFilePath,

     [Parameter(Mandatory=$true, 
          HelpMessage="Safe Haven Management environment ('test' for test and 'prod' for production")]
     [ValidateSet('test','prod')]
     [string]$shmId
)

# Set SHM specific parameters from SHM ID
if ($ShmId -eq 'test') {
     $domain="dsgroupdev.co.uk";
     $userOuPath="OU=Safe Haven Research Users,DC=dsgroupdev,DC=co,DC=uk";
} elseif ($shmId -eq 'prod') {
     $domain="turingsafehaven.ac.uk";
     $userOuPath="OU=Safe Haven Research Users,DC=turingsafehaven,DC=ac,DC=uk";
}

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
Import-Module ADSync
Start-ADSyncSyncCycle -PolicyType Delta