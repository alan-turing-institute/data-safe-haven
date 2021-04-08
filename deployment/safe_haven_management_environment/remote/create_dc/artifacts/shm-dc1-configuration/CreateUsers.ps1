param (
    [Parameter(Mandatory = $true, HelpMessage = "Path to the CSV file of users")]
    [ValidateNotNullOrEmpty()]
    [string]$userFilePath
)

$domain = (Get-ADForest -Current LocalComputer).Domains
$userOuPath = (Get-ADObject -Filter * | Where-Object { $_.Name -eq "Safe Haven Research Users" }).DistinguishedName

Add-Type -AssemblyName System.Web
$Description = "Research User"

Import-Csv $userFilePath | ForEach-Object {
    $UserPrincipalName = "$($_.SamAccountName)@${domain}"
    $DisplayName = "$($_.GivenName) $($_.Surname)"
    $password = [System.Web.Security.Membership]::GeneratePassword(12, 3)
    $props = @{
        SamAccountName       = $_.SamAccountName
        UserPrincipalName    = $UserPrincipalName
        Name                 = "$DisplayName"
        DisplayName          = "$DisplayName"
        GivenName            = $_.GivenName
        SurName              = $_.Surname
        Department           = $Department
        Description          = $Description
        Path                 = "$userOuPath"
        Enabled              = $True
        AccountPassword      = (ConvertTo-SecureString $Password -AsPlainText -Force)
        PasswordNeverExpires = $False
        Mobile               = $_.Mobile
        Email                = $UserPrincipalName
        Country              = "GB"
    }

    # Create user and add them to the group if requested
    try {
        New-ADUser @props -PassThru
        if ($_.GroupName) {
            foreach ($group in $($_.GroupName.Split("|"))) {
                Write-Output "Adding user to group '$group'"
                Add-ADGroupMember "$group" $props.SamAccountName
            }
        }
        Write-Output "Created a user with UserPrincipalName '$UserPrincipalName'"
    } catch [Microsoft.ActiveDirectory.Management.ADIdentityAlreadyExistsException] {
        Write-Output "User with UserPrincipalName '$UserPrincipalName' already exists"
    }
}

# Force sync with AzureAD. It will still take around 5 minutes for changes to propagate
Write-Output "Synchronising locally Active Directory with Azure"
Import-Module -Name "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync" -ErrorAction Stop
Start-ADSyncSyncCycle -PolicyType Delta
