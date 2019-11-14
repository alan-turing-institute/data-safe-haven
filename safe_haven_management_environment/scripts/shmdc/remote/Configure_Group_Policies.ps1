# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command

Write-Host "Configuring group policies"

# Get SID for the Local Administrators group
$groupSID = ""
$gpo = Get-GPO -Name "All servers - Local Administrators"
[xml]$gpoReportXML = Get-GPOReport -Guid $gpo.ID -ReportType xml
foreach ($group in $gpoReportXML.GPO.Computer.ExtensionData.Extension.RestrictedGroups) {
  if ($group.GroupName.Name.'#text' -eq "BUILTIN\Administrators") {
    $groupSID = $group.GroupName.SID.'#text'
  }
}
Write-Host "Found the 'Local Administrators' group: $groupSID"

# Write GptTmpl file
$GptTmplString = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Group Membership]
*${groupSID}__Memberof =
*${groupSID}__Members = SG Safe Haven Server Administrators
"@
Set-Content -Path "F:\SYSVOL\domain\Policies\{$($gpo.ID)}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf" -Value "$GptTmplString"
if ($?) {
  Write-Host " [o] Successfully set group policies for 'Local Administrators'"
} else {
  Write-Host " [x] Failed to set group policies for 'Local Administrators'"
}
