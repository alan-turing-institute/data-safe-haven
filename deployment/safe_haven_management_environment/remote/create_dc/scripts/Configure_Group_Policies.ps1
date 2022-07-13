# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Fully-qualified SHM domain name")]
    [string]$shmFqdn,
    [Parameter(HelpMessage = "Name of the server administrator group")]
    [string]$serverAdminSgName
)


# Get SID for the Local Administrators group
# ------------------------------------------
$localAdminGroupSID = ""
$localAdminGpo = Get-GPO -Name "All servers - Local Administrators"
[xml]$gpoReportXML = Get-GPOReport -Guid $localAdminGpo.ID -ReportType xml
foreach ($group in $gpoReportXML.GPO.Computer.ExtensionData.Extension.RestrictedGroups) {
    if ($group.GroupName.Name.'#text' -eq "BUILTIN\Administrators") {
        $localAdminGroupSID = $group.GroupName.SID.'#text'
    }
}
Write-Output "Found the 'Local Administrators' group: $localAdminGroupSID"


# Edit GptTmpl file controlling which domain users should be considered local administrators
# ------------------------------------------------------------------------------------------
Write-Output "Ensuring that members of '${serverAdminSgName}' are local administrators"
$GptTmplString = @"
[Unicode]
Unicode=yes
[Version]
signature="`$CHICAGO`$"
Revision=1
[Group Membership]
*${localAdminGroupSID}__Memberof =
*${localAdminGroupSID}__Members = ${serverAdminSgName}
"@
Set-Content -Path "C:\ActiveDirectory\SYSVOL\domain\Policies\{$($localAdminGpo.ID)}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf" -Value "$GptTmplString"
if ($?) {
    Write-Output " [o] Successfully set group policies for 'Local Administrators'"
} else {
    Write-Output " [x] Failed to set group policies for 'Local Administrators'"
}


# Set the layout file for the Remote Desktop servers
# --------------------------------------------------
Write-Output "Setting the layout file for the Remote Desktop servers..."
$null = Set-GPRegistryValue -Key "HKCU\Software\Policies\Microsoft\Windows\Explorer\" `
                            -Name "Session Servers - Remote Desktop Control" `
                            -Type "ExpandString" `
                            -ValueName "StartLayoutFile" `
                            -Value "\\${shmFqdn}\SYSVOL\${shmFqdn}\scripts\ServerStartMenu\LayoutModification.xml"
if ($?) {
    Write-Output " [o] Succeeded"
} else {
    Write-Output " [x] Failed!"
}
