# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [String]$dataMountSamAccountName,
    [String]$dsvmLdapSamAccountName,
    [String]$gitlabLdapSamAccountName,
    [String]$hackmdLdapSamAccountName,
    [String]$rdsDataserverVMName,
    [String]$rdsGatewayVMName,
    [String]$rdsSessionHostAppsVMName,
    [String]$rdsSessionHostDesktopVMName,
    [String]$rdsSessionHostReviewVMName,
    [String]$researchUserSgName,
    [String]$reviewUserSgName,
    [String]$sqlAdminSgName,
    [String]$sreId,
    [String]$testResearcherSamAccountName
)

function Remove-SreUser($samAccountName) {
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

function Remove-SreComputer($computerName) {
    if (Get-ADComputer -Filter "Name -eq '$computerName'") {
        Write-Host " [ ] Removing computer '$computerName'"
        Get-ADComputer $computerName | Remove-ADObject -Recursive -Confirm:$False
        if ($?) {
            Write-Host " [o] Succeeded"
        } else {
            Write-Host " [x] Failed"
            exit 1
        }
    } else {
        Write-Host "No computer named '$computerName' exists"
    }
}

function Remove-SreGroup($groupName) {
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

# Remove users
Remove-SreUser $dataMountSamAccountName
Remove-SreUser $dsvmLdapSamAccountName
Remove-SreUser $gitlabLdapSamAccountName
Remove-SreUser $hackmdLdapSamAccountName
Remove-SreUser $testResearcherSamAccountName

# Remove groups
Remove-SreGroup $researchUserSgName
Remove-SreGroup $reviewUserSgName
Remove-SreGroup $sqlAdminSgName

# Remove service computers
Remove-SreComputer $rdsDataserverVMName
Remove-SreComputer $rdsGatewayVMName
Remove-SreComputer $rdsSessionHostAppsVMName
Remove-SreComputer $rdsSessionHostDesktopVMName
Remove-SreComputer $rdsSessionHostDesktopVMName

# Remove DSVMs
$dsvmPrefix = "SRE-$sreId".Replace(".","-").ToUpper()
foreach ($dsvm in $(Get-ADComputer -Filter "Name -like '$dsvmPrefix*'")) {
    Remove-SreComputer $dsvm.Name
}
