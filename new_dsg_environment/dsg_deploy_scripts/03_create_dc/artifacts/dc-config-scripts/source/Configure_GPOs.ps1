Param(
  [Parameter(Mandatory = $true, HelpMessage="Enter Path to GPO backup files")]
  [ValidateNotNullOrEmpty()]
  [string]$gpoBackupPath,
  [Parameter(Mandatory = $true, HelpMessage="DSG Netbios name")]
  [ValidateNotNullOrEmpty()]
  [string]$dsgNetbiosName,
  [Parameter(Mandatory = $true, HelpMessage="DSG DN")]
  [ValidateNotNullOrEmpty()]
  [string]$dsgDn
)

#Import GPOs into Domain
Import-GPO -BackupId 0AF343A0-248D-4CA5-B19E-5FA46DAE9F9C -TargetName "All servers – Local Administrators" -Path $gpoBackupPath -CreateIfNeeded
Import-GPO -BackupId D320C1D9-52EF-47D8-80A7-1E73A457CDAD -TargetName "Research Users – Mapped Drives" -Path $gpoBackupPath -CreateIfNeeded
Import-GPO -BackupId EE9EF278-1F3F-461C-9F7A-97F2B82C04B4 -TargetName "All Servers – Windows Update" -Path $gpoBackupPath -CreateIfNeeded
Import-GPO -BackupId B0A14FC3-292E-4A23-B280-9CC172D92FD5 -TargetName "Session Servers – Remote Desktop Control" -Path $gpoBackupPath -CreateIfNeeded
Import-GPO -BackupId 742211F9-1482-4D06-A8DE-BA66101933EB -TargetName "All Servers – Windows Services" -Path $gpoBackupPath -CreateIfNeeded

#Link GPO with OUs
Get-GPO -Name "All servers – Local Administrators" | New-GPLink -Target "OU=$dsgNetbiosName Data Servers,$dsgDn" -LinkEnabled Yes
Get-GPO -Name "All servers – Local Administrators" | New-GPLink -Target "OU=$dsgNetbiosName RDS Session Servers,$dsgDn" -LinkEnabled Yes
Get-GPO -Name "All servers – Local Administrators" | New-GPLink -Target "OU=$dsgNetbiosName Service Servers,$dsgDn" -LinkEnabled Yes

Get-GPO -Name "All Servers – Windows Services" | New-GPLink -Target "OU=Domain Controllers,$dsgDn" -LinkEnabled Yes
Get-GPO -Name "All Servers – Windows Services" | New-GPLink -Target "OU=$dsgNetbiosName Data Servers,$dsgDn" -LinkEnabled Yes
Get-GPO -Name "All Servers – Windows Services" | New-GPLink -Target "OU=$dsgNetbiosName RDS Session Servers,$dsgDn" -LinkEnabled Yes
Get-GPO -Name "All Servers – Windows Services" | New-GPLink -Target "OU=$dsgNetbiosName Service Servers,$dsgDn" -LinkEnabled Yes

Get-GPO -Name "All Servers – Windows Update" | New-GPLink -Target "OU=Domain Controllers,$dsgDn" -LinkEnabled Yes
Get-GPO -Name "All Servers – Windows Update" | New-GPLink -Target "OU=$dsgNetbiosName Data Servers,$dsgDn" -LinkEnabled Yes
Get-GPO -Name "All Servers – Windows Update" | New-GPLink -Target "OU=$dsgNetbiosName RDS Session Servers,$dsgDn" -LinkEnabled Yes
Get-GPO -Name "All Servers – Windows Update" | New-GPLink -Target "OU=$dsgNetbiosName Service Servers,$dsgDn" -LinkEnabled Yes

Get-GPO -Name "Research Users – Mapped Drives" | New-GPLink -Target "OU=$dsgNetbiosName RDS Session Servers,$dsgDn" -LinkEnabled Yes

Get-GPO -Name "Session Servers – Remote Desktop Control" | New-GPLink -Target "OU=$dsgNetbiosName RDS Session Servers,$dsgDn" -LinkEnabled Yes
