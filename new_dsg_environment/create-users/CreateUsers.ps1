Param (
        [Parameter(Mandatory=$true, 
             HelpMessage="Path to the CSV file of users")]
        [ValidateNotNullOrEmpty()]
        [string]$UserFilePath,

        [Parameter(Mandatory=$true, 
             HelpMessage="FQDN of the domain i.e. TuringSafeHaven.ac.uk")]
        [ValidateNotNullOrEmpty()]
        [string]$domain,

        [Parameter(Mandatory=$true, 
             HelpMessage="OU path of the user container, MUST be in quotes! i.e OU=Safe Haven Research Users,DC=dsgroupdev,DC=co,DC=uk")]
        [ValidateNotNullOrEmpty()]
        [string]$UserOUPath
 )

Add-Type -AssemblyName System.Web
$Description = "Research User"

Import-Csv $UserFilePath | foreach-object {
$UserPrincipalName = $_.AccountName + "@" + "$domain"
$password = [System.Web.Security.Membership]::GeneratePassword(12,3)
New-ADUser  -SamAccountName $_.AccountName `
            -UserPrincipalName $UserPrincipalName `
            -Name "$($_.GivenName) $($_.Surname)" `
            -DisplayName "$($_.GivenName) $($_.Surname)" `
            -GivenName $_.GivenName `
            -SurName $_.Surname `
            -Department $Department `
            -Description $Description `
            -Path $UserOUPath `
            -Enabled $True `
            -AccountPassword (ConvertTo-SecureString $Password -AsPlainText -force) `
            -PasswordNeverExpires $False `
            -PassThru `
            -Mobile $_.Mobile `
            -Email $UserPrincipalName `
            -Country GB
    }
