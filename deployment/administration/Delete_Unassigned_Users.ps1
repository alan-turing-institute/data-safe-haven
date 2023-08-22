# Extract list of users
$userOuPath = (Get-ADObject -Filter * | Where-Object { $_.Name -eq "Safe Haven Research Users" }).DistinguishedName
$users = Get-ADUser -Filter * -SearchBase "$userOuPath" -Properties *
foreach ($user in $users) {
    $groupName = ($user | Select-Object -ExpandProperty MemberOf | ForEach-Object { (($_ -Split ",")[0] -Split "=")[1] }) -join "|"
    $user | Add-Member -NotePropertyName GroupName -NotePropertyValue $groupName -Force
}

# Delete users not found in any group (with exception for named SG e.g. "Sandbox")
foreach ($user in $users) {
    if (!($user.GroupName)) {
        $name = $user.SamAccountName
        Remove-ADUser -Identity $name
    }
}

# Force sync with AzureAD. It will still take around 5 minutes for changes to propagate
Write-Output "Synchronising locally Active Directory with Azure"
try {
    Import-Module -Name "C:\Program Files\Microsoft Azure AD Sync\Bin\ADSync" -ErrorAction Stop
    Start-ADSyncSyncCycle -PolicyType Delta
}
catch [System.IO.FileNotFoundException] {
    Write-Output "Skipping as Azure AD Sync is not installed"
}
catch {
    Write-Output "Unable to run Azure Active Directory synchronisation!"
}