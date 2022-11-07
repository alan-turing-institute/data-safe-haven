$UserOuPath = (Get-ADObject -Filter * | Where-Object { $_.Name -eq "Data Safe Haven Research Users" }).DistinguishedName
foreach ($User in $(Get-ADUser -Filter * -SearchBase $UserOuPath -Properties TelephoneNumber,Mail)) {
    Write-Output "$($User.SamAccountName);$($User.GivenName);$($User.Surname);$($User.TelephoneNumber);$($User.Mail);$($User.UserPrincipalName)"
}
