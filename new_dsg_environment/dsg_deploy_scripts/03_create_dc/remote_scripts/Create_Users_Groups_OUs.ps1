# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
  [Parameter(Position=0, HelpMessage = "SRE Netbios name")]
  [string]$sreNetbiosName,
  [Parameter(Position=1, HelpMessage = "SRE DN")]
  [string]$sreDn,
  [Parameter(Position=2, HelpMessage = "SRE Server admin security group name")]
  [string]$sreServerAdminSgName,
  [Parameter(Position=3, HelpMessage = "SRE DC admin username")]
  [string]$sreDcAdminUsername
)

# Set DC admin user account password to never expire
# --------------------------------------------------
Write-Host "Setting password for '$sreDcAdminUsername' to never expire"
Set-ADUser -Identity "$sreDcAdminUsername" -PasswordNeverExpires $true
if ($?) {
  Write-Host " [o] Succeeded"
} else {
  Write-Host " [x] Failed!"
}


# Create OUs
# ----------
Write-Host "Creating OUs..."
ForEach($ouDescription in ("Data Servers", "RDS Session Servers", "Security Groups", "Service Accounts", "Service Servers")) {
  $ouName = "$sreNetbiosName $ouDescription"
  $ouExists = Get-ADOrganizationalUnit -Filter "Name -eq '$ouName'"
  if ("$ouExists" -ne "") {
    Write-Host " [o] OU '$ouName' already exists"
  } else {
    New-ADOrganizationalUnit -Name "$ouName" -Description "$ouDescription"
    if ($?) {
      Write-Host " [o] OU '$ouName' created successfully"
    } else {
      Write-Host " [x] OU '$ouName' creation failed!"
    }
  }
}


# Create security groups
# ----------------------
Write-Host "Creating security groups..."
ForEach($groupName in ("$sreServerAdminSgName")) {
  $groupExists = $(Get-ADGroup -Filter "Name -eq '$groupName'").Name
  if ("$groupExists" -ne "") {
    Write-Host " [o] Security group '$groupName' already exists"
  } else {
    Write-Host "New-ADGroup -Name '$groupName' -GroupScope Global -Description '$groupName' -GroupCategory Security -Path 'OU=$sreNetbiosName Security Groups,$sreDn'"
    New-ADGroup -Name "$groupName" -GroupScope Global -Description "$groupName" -GroupCategory Security -Path "OU=$sreNetbiosName Security Groups,$sreDn"
    if ($?) {
      Write-Host " [o] Security group '$groupName' created successfully"
    } else {
      Write-Host " [x] Security group '$groupName' creation failed!"
    }
  }
}


# New-ADGroup -Name "$sreServerAdminSgName" -GroupScope Global -Description "$sreServerAdminSgName" -GroupCategory Security -Path "OU=$sreNetbiosName Security Groups,$sreDn"
# if ($?) {
#   Write-Host " [o] Created '$sreServerAdminSgName' group"
# } else {
#   Write-Host " [x] Failed to create '$sreServerAdminSgName' group!"
# }
Add-ADGroupMember "$sreServerAdminSgName" "$sreDcAdminUsername"
if ($?) {
  Write-Host " [o] Added '$sreDcAdminUsername' to '$sreServerAdminSgName' group"
} else {
  Write-Host " [x] Failed to add '$sreDcAdminUsername' to '$sreServerAdminSgName' group!"
}