# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  [Parameter(Position=0, HelpMessage = "DSG DN")]
  [string]$dsgDn,
  [Parameter(Position=1, HelpMessage = "DSG Netbios name")]
  [string]$dsgNetbiosName,
  [Parameter(Position=2, HelpMessage = "RDS Gateway hostname")]
  [string]$gatewayHostname,
  [Parameter(Position=3, HelpMessage = "RDS Session Host 1 hostname")]
  [string]$sh1Hostname,
  [Parameter(Position=4, HelpMessage = "RDS Session Host 2 hostname")]
  [string]$sh2Hostname
)

$gatewayIdentity = "CN=$gatewayHostname,CN=Computers,$dsgDn"
$gatewayTargetPath = "OU=$dsgNetbiosName Service Servers,$dsgDn"
$sh1Identity = "CN=$sh1Hostname,CN=Computers,$dsgDn"
$sh2Identity = "CN=$sh2Hostname,CN=Computers,$dsgDn"
$shTargetPath = "OU=$dsgNetbiosName RDS Session Servers,$dsgDn"

Write-Output "Moving '$gatewayIdentity' to '$gatewayTargetPath'"
Move-ADObject -Identity "$gatewayIdentity" -TargetPath "$gatewayTargetPath"
Write-Output "Moving '$sh1Identity' to '$shTargetPath'"
Move-ADObject -Identity "$sh1Identity" -TargetPath "$shTargetPath"
Write-Output "Moving '$sh2Identity' to '$shTargetPath'"
Move-ADObject -Identity "$sh2Identity" -TargetPath "$shTargetPath"