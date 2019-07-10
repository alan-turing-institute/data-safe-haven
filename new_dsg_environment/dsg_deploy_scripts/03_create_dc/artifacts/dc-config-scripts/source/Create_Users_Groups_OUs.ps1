Param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "DSG Netbios name")]
  [string]$dsgNetbiosName,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "DSG DN")]
  [string]$dsgDn,
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "DSG Server admin security group name")]
  [string]$dsgServerAdminSgName,
  [Parameter(Position=3, Mandatory = $true, HelpMessage = "DSG DC admin username")]
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
