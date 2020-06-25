# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Position = 0, HelpMessage = "SHM DN")]
    [string]$shmDn,
    [Parameter(Position = 1, HelpMessage = "RDS Gateway hostname")]
    [string]$gatewayHostname,
    [Parameter(Position = 2, HelpMessage = "RDS Session Host 1 hostname")]
    [string]$sh1Hostname,
    [Parameter(Position = 3, HelpMessage = "RDS Session Host 2 hostname")]
    [string]$sh2Hostname
)

$gatewayTargetPath = "OU=Secure Research Environment Service Servers,$shmDn"
$shTargetPath = "OU=Secure Research Environment RDS Session Servers,$shmDn"

Write-Output " [ ] Moving '$gatewayHostname' to '$gatewayTargetPath'"
Move-ADObject (Get-ADComputer -Identity $gatewayHostname) -TargetPath "$gatewayTargetPath"
if ($?) {
    Write-Host " [o] Completed"
} else {
    Write-Host " [x] Failed"
}

Write-Output " [ ] Moving '$sh1Hostname' to '$shTargetPath'"
Move-ADObject (Get-ADComputer -Identity $sh1Hostname)  -TargetPath "$shTargetPath"
if ($?) {
    Write-Host " [o] Completed"
} else {
    Write-Host " [x] Failed"
}

Write-Output " [ ] Moving '$sh2Hostname' to '$shTargetPath'"
Move-ADObject (Get-ADComputer -Identity $sh2Hostname)  -TargetPath "$shTargetPath"
if ($?) {
    Write-Host " [o] Completed"
} else {
    Write-Host " [x] Failed"
}