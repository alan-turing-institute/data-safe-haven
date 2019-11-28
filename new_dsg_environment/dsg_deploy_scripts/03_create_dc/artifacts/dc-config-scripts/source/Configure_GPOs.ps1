# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
  [Parameter(HelpMessage="Enter Path to GPO backup files")]
  [ValidateNotNullOrEmpty()]
  [string]$gpoBackupPath,
  [Parameter(HelpMessage="DSG Netbios name")]
  [ValidateNotNullOrEmpty()]
  [string]$dsgNetbiosName,
  [Parameter(HelpMessage="DSG DN")]
  [ValidateNotNullOrEmpty()]
  [string]$dsgDn,
  [Parameter(HelpMessage="DSG FQDN")]
  [ValidateNotNullOrEmpty()]
  [string]$dsgFqdn
)

# Import GPOs into Domain
Write-Output "   - Importing GPOs from backup"
$_ = Import-GPO -BackupId 0AF343A0-248D-4CA5-B19E-5FA46DAE9F9C -TargetName "All servers – Local Administrators" -Path $gpoBackupPath -CreateIfNeeded
$_ = Import-GPO -BackupId D320C1D9-52EF-47D8-80A7-1E73A457CDAD -TargetName "Research Users – Mapped Drives" -Path $gpoBackupPath -CreateIfNeeded
$_ = Import-GPO -BackupId EE9EF278-1F3F-461C-9F7A-97F2B82C04B4 -TargetName "All Servers – Windows Update" -Path $gpoBackupPath -CreateIfNeeded
$_ = Import-GPO -BackupId B0A14FC3-292E-4A23-B280-9CC172D92FD5 -TargetName "Session Servers – Remote Desktop Control" -Path $gpoBackupPath -CreateIfNeeded
$_ = Import-GPO -BackupId 742211F9-1482-4D06-A8DE-BA66101933EB -TargetName "All Servers – Windows Services" -Path $gpoBackupPath -CreateIfNeeded

# Link GPO with OUs
Write-Output "   - Linking GPOs with OUs"
$_ = Get-GPO -Name "All servers – Local Administrators" | New-GPLink -Target "OU=$dsgNetbiosName Data Servers,$dsgDn" -LinkEnabled Yes
$_ = Get-GPO -Name "All servers – Local Administrators" | New-GPLink -Target "OU=$dsgNetbiosName RDS Session Servers,$dsgDn" -LinkEnabled Yes
$_ = Get-GPO -Name "All servers – Local Administrators" | New-GPLink -Target "OU=$dsgNetbiosName Service Servers,$dsgDn" -LinkEnabled Yes

$_ = Get-GPO -Name "All Servers – Windows Services" | New-GPLink -Target "OU=Domain Controllers,$dsgDn" -LinkEnabled Yes
$_ = Get-GPO -Name "All Servers – Windows Services" | New-GPLink -Target "OU=$dsgNetbiosName Data Servers,$dsgDn" -LinkEnabled Yes
$_ = Get-GPO -Name "All Servers – Windows Services" | New-GPLink -Target "OU=$dsgNetbiosName RDS Session Servers,$dsgDn" -LinkEnabled Yes
$_ = Get-GPO -Name "All Servers – Windows Services" | New-GPLink -Target "OU=$dsgNetbiosName Service Servers,$dsgDn" -LinkEnabled Yes

$_ = Get-GPO -Name "All Servers – Windows Update" | New-GPLink -Target "OU=Domain Controllers,$dsgDn" -LinkEnabled Yes
$_ = Get-GPO -Name "All Servers – Windows Update" | New-GPLink -Target "OU=$dsgNetbiosName Data Servers,$dsgDn" -LinkEnabled Yes
$_ = Get-GPO -Name "All Servers – Windows Update" | New-GPLink -Target "OU=$dsgNetbiosName RDS Session Servers,$dsgDn" -LinkEnabled Yes
$_ = Get-GPO -Name "All Servers – Windows Update" | New-GPLink -Target "OU=$dsgNetbiosName Service Servers,$dsgDn" -LinkEnabled Yes

$_ = Get-GPO -Name "Research Users – Mapped Drives" | New-GPLink -Target "OU=$dsgNetbiosName RDS Session Servers,$dsgDn" -LinkEnabled Yes

$_ = Get-GPO -Name "Session Servers – Remote Desktop Control" | New-GPLink -Target "OU=$dsgNetbiosName RDS Session Servers,$dsgDn" -LinkEnabled Yes

# Fix the GPO Settings for "Session Servers – Remote Desktop Control"
$_ = Set-GPRegistryValue -Name "Session Servers – Remote Desktop Control" -Type "ExpandString" -Key "HKCU\Software\Policies\Microsoft\Windows\Explorer\" -ValueName "StartLayoutFile" -Value "\\$dsgFqdn\SYSVOL\$dsgFqdn\scripts\ServerStartMenu\LayoutModifcation.xml"
 

# Fix the GPO Settings for "All servers – Local Administrators" 

$gpoGuid = ((Get-GPO -Name "All servers – Local Administrators").Id.Guid).ToUpper()
$domainUsersGuid = (Get-ADGroup "Domain Admins").SID.Value
$serverAdminGuid = (Get-ADGroup "SG $dsgNetbiosName Server Administrators").SID.Value
$oldGUID1 =  "S-1-5-21-1813578418-120617354-939478454-512"
$oldGUID2 = "S-1-5-21-1813578418-120617354-939478454-1108"
$GPTemplate = "\\$dsgFqdn\sysvol\$dsgFqdn\Policies\{$gpoGuid}\Machine\microsoft\windows nt\SecEdit\GptTmpl.inf"

 
## Replace GP Template with the new GUIDS
$_ = ((Get-Content -path $GPTemplate -Raw ) -Replace $oldGUID1, $domainUsersGuid) | Set-Content -Path $GPTemplate
$_ = ((Get-Content -path $GPTemplate -Raw ) -Replace $oldGUID2, $serverAdminGuid) | Set-Content -Path $GPTemplate