# Extract list of users
# ---------------------
Write-Output "Exporting user list..."
$userOuPath = (Get-ADObject -Filter * | Where-Object { $_.Name -eq "Safe Haven Research Users" }).DistinguishedName
$users = Get-ADUser -Filter * -SearchBase "$userOuPath" -Properties *
foreach ($user in $users) {
    $groupName = ($user | Select-Object -ExpandProperty MemberOf | ForEach-Object { (($_ -Split ",")[0] -Split "=")[1] }) -join "|"
    $user | Add-Member -NotePropertyName GroupName -NotePropertyValue $groupName -Force
}

# Delete users not found in any group (with exception for named SG e.g. "Sandbox")
# --------------------------------------------------------------------------------
Write-Output "Deleting users not in any security group..."
foreach ($user in $users) {
    if (!($user.GroupName)) {
        $name = $user.SamAccountName
        Remove-ADUser -Identity $name
        Write-Out "Deleted $name"
    }
}