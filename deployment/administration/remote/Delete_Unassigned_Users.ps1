param(
    [Parameter(Mandatory = $true, HelpMessage = "yes/no determines whether users should actually be deleted")]
    [string]$dryRun
)

# Extract list of users
$userOuPath = (Get-ADObject -Filter * | Where-Object { $_.Name -eq "Safe Haven Research Users" }).DistinguishedName
$users = Get-ADUser -Filter * -SearchBase "$userOuPath" -Properties *
foreach ($user in $users) {
    $groupName = ($user | Select-Object -ExpandProperty MemberOf | ForEach-Object { (($_ -Split ",")[0] -Split "=")[1] }) -join "|"
    if (!($groupName)) {
        $name = $user.SamAccountName
        if ($dryRun -eq "yes") {
            Write-Output "User $name would be deleted by this action"
        } else {
            Write-Output "Deleting $name"
            Remove-ADUser -Identity $name -Confirm:$false
        }
    }
}

# Force sync with AzureAD. It will still take around 5 minutes for changes to propagate
if ($dryRun -eq "no") {
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
}