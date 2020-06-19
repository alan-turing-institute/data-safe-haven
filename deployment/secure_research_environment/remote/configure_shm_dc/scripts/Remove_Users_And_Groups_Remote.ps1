# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [string]$groupNamesJoined,
    [string]$userNamesJoined,
    [string]$computerNamePatternsJoined
)

# Remove users
foreach ($samAccountName in $userNamesJoined.Split("|")) {
    if (Get-ADUser -Filter "SamAccountName -eq '$samAccountName'") {
        Write-Host " [ ] Removing user '$samAccountName'"
        Remove-ADUser (Get-AdUser $samAccountName) -Confirm:$False
        if ($?) {
            Write-Host " [o] Succeeded"
        } else {
            Write-Host " [x] Failed"
            exit 1
        }
    } else {
        Write-Host "No user named '$samAccountName' exists"
    }
}

# Remove computers
foreach ($computerNamePattern in $computerNamePatternsJoined.Split("|")) {
    foreach ($computer in $(Get-ADComputer -Filter "Name -like '$computerNamePattern'")) {
        Write-Host " [ ] Removing computer '$($computer.Name)'"
        $computer | Remove-ADObject -Recursive -Confirm:$False
        if ($?) {
            Write-Host " [o] Succeeded"
        } else {
            Write-Host " [x] Failed"
            exit 1
        }
    }
}

# Remove groups
foreach ($groupName in $groupNamesJoined.Split("|")) {
    if (Get-ADGroup -Filter "Name -eq '$groupName'") {
        Write-Host " [ ] Removing group '$groupName'"
        Remove-ADGroup (Get-ADGroup $groupName) -Confirm:$False
        if ($?) {
            Write-Host " [o] Succeeded"
        } else {
            Write-Host " [x] Failed"
            exit 1
        }
    } else {
        Write-Host "No group named '$groupName' exists"
    }
}
