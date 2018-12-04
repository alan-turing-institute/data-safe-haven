Param (
    [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$Environment,
    [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]$UserFilePath
 )

Switch($Environment) {
    "Testing" {
        $ManagementSubscriptionName = "Safe Haven Management Testing"
        $ActiveDirectoryDomain = "dsgroupdev.co.uk"
        $Department = "OU=Safe Haven Research Users"
        $Path = "DC=dsgroupdev,DC=co,DC=uk"
    }
    default { Throw "Environment " + $Environment + " not supported" }

}
Write-Host "Using subscription " + $ManagementSubscriptionName
Set-AzContext -Subscription $ManagementSubscriptionName

Add-Type -AssemblyName System.Web

Import-Csv $UserFilePath | foreach-object {
$UserPrincipalName = $_.SamAccountName + "@" + $ActiveDirectoryDomain
New-ADUser  -SamAccountName $_.SamAccountName `
            -UserPrincipalName $UserPrincipalName `
            -Name $_.displayname `
            -DisplayName $_.GivenName + " " + $_.SurName  `
            -GivenName $_.cn `
            -SurName $_.sn `
            -Department $Department `
            -Description $_.DisplayName `
            -Path $_.Path `
            -AccountPassword (ConvertTo-SecureString [System.Web.Security.Membership]::GeneratePassword(12,3)
 -AsPlainText -force) `
            -Enabled $True `
            -PasswordNeverExpires $False `
            -PassThru `
            -Mobile $_.Mobile `
            -Email $UserPrincipalName
             }