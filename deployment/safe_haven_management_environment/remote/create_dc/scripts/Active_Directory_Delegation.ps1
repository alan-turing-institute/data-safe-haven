# # Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# # and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# # command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# # C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# # job, but this does not seem to have an immediate effect
# # For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
# param(
#     [Parameter(Position = 0,HelpMessage = "NetBios name")]
#     [ValidateNotNullOrEmpty()]
#     [string]$netbiosName,
#     [Parameter(Position = 1,HelpMessage = "LDAP users group")]
#     [ValidateNotNullOrEmpty()]
#     [string]$ldapUsersSgName
# )

# Import-Module ActiveDirectory

# # Get a handle on the computers AD container
# $computersContainer = Get-ADObject -Filter "Name -eq 'Computers'"

# # Give 'generic read', 'generic write', 'create child' and 'delete child' permissions on the computers container to the LDAP users group
# dsacls $computersContainer /G "$netbiosname\$($ldapUsersSgName):GRGWCCDC"
# if ($?) {
#     Write-Host " [o] Successfully delegated Active Directory permissions"
# } else {
#     Write-Host " [x] Failed to delegate Active Directory permissions"
# }
