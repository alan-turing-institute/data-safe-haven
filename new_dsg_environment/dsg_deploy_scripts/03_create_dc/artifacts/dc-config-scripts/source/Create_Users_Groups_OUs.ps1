# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
  [Parameter(Position=0, HelpMessage = "DSG Netbios name")]
  [string]$dsgNetbiosName,
  [Parameter(Position=1, HelpMessage = "DSG DN")]
  [string]$dsgDn,
  [Parameter(Position=2, HelpMessage = "DSG Server admin security group name")]
  [string]$dsgServerAdminSgName,
  [Parameter(Position=3, HelpMessage = "DSG DC admin username")]
  [string]$dsgDcAdminUsername
)

# Set DC admin user account password to never expire
Set-ADUser -Identity "$dsgDcAdminUsername" -PasswordNeverExpires $true

# Create OUs
New-ADOrganizationalUnit -Name "$dsgNetbiosName Data Servers" -Description "Data Servers"
New-ADOrganizationalUnit -Name "$dsgNetbiosName RDS Session Servers" -Description "RDS Session Servers"
New-ADOrganizationalUnit -Name "$dsgNetbiosName Security Groups" -Description "Security Groups"
New-ADOrganizationalUnit -Name "$dsgNetbiosName Service Accounts" -Description "Service Accounts"
New-ADOrganizationalUnit -Name "$dsgNetbiosName Service Servers" -Description "Service Servers"

# Server administrators
New-ADGroup -Name "$dsgServerAdminSgName" -GroupScope Global -Description "$dsgServerAdminSgName" -GroupCategory Security -Path "OU=$dsgNetbiosName Security Groups,$dsgDn"
Add-ADGroupMember "$dsgServerAdminSgName" "$dsgDcAdminUsername"
