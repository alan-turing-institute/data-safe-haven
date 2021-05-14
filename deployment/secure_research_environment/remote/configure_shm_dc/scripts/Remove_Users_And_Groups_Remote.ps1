# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $false, HelpMessage = "Base64-encoded list of SRE groups")]
    [string]$groupNamesB64,
    [Parameter(Mandatory = $false, HelpMessage = "Base64-encoded list of SRE users")]
    [string]$userNamesB64,
    [Parameter(Mandatory = $false, HelpMessage = "Base64-encoded list of SRE computers")]
    [string]$computerNamePatternsB64
)

# Unserialise JSON and read into PSCustomObject
$groupNames = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($groupNamesB64)) | ConvertFrom-Json
$userNames = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($userNamesB64)) | ConvertFrom-Json
$computerNamePatterns = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($computerNamePatternsB64)) | ConvertFrom-Json

# Remove users
Write-Output "Removing SRE users..."
foreach ($samAccountName in $userNames) {
    if (Get-ADUser -Filter "SamAccountName -eq '$samAccountName'") {
        Remove-ADUser (Get-ADUser $samAccountName) -Confirm:$False
        if ($?) {
            Write-Output " [o] Successfully removed user '$samAccountName'"
        } else {
            Write-Output " [x] Failed to remove user '$samAccountName'!"
            exit 1
        }
    } else {
        Write-Output "No user named '$samAccountName' exists"
    }
}

# Remove computers
Write-Output "Removing SRE computers..."
foreach ($computerNamePattern in $computerNamePatterns) {
    foreach ($computer in $(Get-ADComputer -Filter "Name -like '$computerNamePattern'")) {
        $computer | Remove-ADObject -Recursive -Confirm:$False
        if ($?) {
            Write-Output " [o] Successfully removed computer '$($computer.Name)'"
        } else {
            Write-Output " [x] Failed to remove computer '$($computer.Name)'!"
            exit 1
        }
    }
}

# Remove groups
Write-Output "Removing SRE groups..."
foreach ($groupName in $groupNames) {
    if (Get-ADGroup -Filter "Name -eq '$groupName'") {
        Remove-ADGroup (Get-ADGroup $groupName) -Confirm:$False
        if ($?) {
            Write-Output " [o] Successfully removed group '$groupName'"
        } else {
            Write-Output " [x] Failed to remove group '$groupName'!"
            exit 1
        }
    } else {
        Write-Output "No group named '$groupName' exists"
    }
}
