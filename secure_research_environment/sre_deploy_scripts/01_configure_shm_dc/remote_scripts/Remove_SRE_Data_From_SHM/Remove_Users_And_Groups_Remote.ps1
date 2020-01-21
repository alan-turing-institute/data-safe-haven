# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    $testResearcherSamAccountName,
    $dsvmLdapSamAccountName,
    $gitlabLdapSamAccountName,
    $hackmdLdapSamAccountName,
    $sreResearchUserSG
)


function Remove-SreUser($samAccountName) {
    $user = Get-ADUser -Filter "SamAccountName -eq '$samAccountName'"
    if ($user) {
        Write-Output " [ ] Removing user '$samAccountName'"
        Remove-ADUser (Get-AdUser $samAccountName) -Confirm:$False
        if ($?) {
            Write-Output " [o] Succeeded"
        } else {
            Write-Output " [x] Failed"
            exit 1
        }
    } else {
        Write-Output "No user named '$samAccountName' exists"
    }
}


function Remove-SreGroup($groupName) {
    $group = Get-ADGroup -Filter "Name -eq '$groupName'"
    if ($group) {
        Write-Output " [ ] Removing group '$groupName'"
        Remove-ADGroup (Get-ADGroup $groupName) -Confirm:$False
        if ($?) {
            Write-Output " [o] Succeeded"
        } else {
            Write-Output " [x] Failed"
            exit 1
        }
    } else {
        Write-Output "No group named '$groupName' exists"
    }
}


# Remove users
Remove-SreUser($testResearcherSamAccountName)
Remove-SreUser($dsvmLdapSamAccountName)
Remove-SreUser($gitlabLdapSamAccountName)
Remove-SreUser($hackmdLdapSamAccountName)

# Remove groups
Remove-SreGroup($sreResearchUserSG)