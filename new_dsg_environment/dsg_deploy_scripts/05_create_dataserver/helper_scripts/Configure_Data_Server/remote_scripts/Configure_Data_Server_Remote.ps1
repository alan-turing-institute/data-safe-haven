param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "DSG Netbios name")]
  [string]$dsgNetbiosName,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "SHM Netbios name")]
  [string]$shmNetbiosName,
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "Security group name for research users")]
  [string]$researcherUserSgName,
  [Parameter(Position=3, Mandatory = $true, HelpMessage = "Security group name for server admins")]
  [string]$serverAdminSgName
)

# Set language and time-zone
Write-Output "Setting system locale"
Set-WinHomeLocation -GeoId 0xf2
Set-TimeZone -Name "GMT Standard Time"
Set-WinSystemLocale en-GB
Set-Culture en-GB
Set-WinUserLanguageList -LanguageList (New-WinUserLanguageList -Language en-GB) -Force

#Format data drive
Stop-Service ShellHWDetection

$rawDisks = @(Get-Disk |  Where {$_.PartitionStyle -eq 'raw'} | Sort -Property Number)
if ($rawDisks.Count -gt 0) {
  Write-Output ("Formatting " + $rawDisks.Count + " raw disks")
  Foreach ($rawDisk in $rawDisks) {
    $LUN = (Get-WmiObject Win32_DiskDrive | Where index -eq $rawDisk.Number | Select SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    $disk = Initialize-Disk -PartitionStyle GPT -Number $rawDisk.Number
    $partition = New-Partition -DiskNumber $rawDisk.Number -UseMaximumSize -AssignDriveLetter
    $label = "DATA-$LUN"
    Write-Output (" - Formatting partition " + $partition.PartitionNumber + " of raw disk " + $rawDisk.Number + " with label '" + $label + "' at drive letter '" + $partition.DriveLetter + "'")
    $volume = Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $label -Confirm:$false
  }
}

Start-Service ShellHWDetection

# Setup disk shares
Write-Output "Configuring disk shares"
$shareDriveLetter = "F"
$shareFolder = "Data"
$sharePath = ($shareDriveLetter + ":\" + $shareFolder)
$shareName = $shareFolder
$researcherUserSg = ($shmNetbiosName + "\" + $researcherUserSgName) 
$serverAdminSg = ($dsgNetbiosName + "\" + $serverAdminSgName)
Write-Output "  - Creating '$shareName' data share at '$sharePath' with the following permissions"
Write-Output "    - FullAccess: $serverAdminSg"
Write-Output "    - ChangeAccess: $researcherUserSg" 

# Create share, being robust to case where share already exists
if(!(Test-Path -Path $sharePath )){
  $_ = New-Item -ItemType directory -Path $sharePath;
}
$_ = New-SmbShare -Path "F:\Data" -Name "Data" -ErrorAction:Continue;

# Revoke all access for our security groups and the "Everyone" group to ensure only the permissions we set explicitly apply
$_ = Revoke-SmbShareAccess -Name $shareName -AccountName $researcherUserSg -Force -ErrorAction:Continue;
$_ = Revoke-SmbShareAccess -Name $shareName -AccountName $serverAdminSg -Force -ErrorAction:Continue;
$_ = Revoke-SmbShareAccess -Name $shareName -AccountName Everyone -Force -ErrorAction:Continue;

# Set the permissions we want explicitly on the share
$_ = Grant-SmbShareAccess -Name $shareName -AccountName $serverAdminSg -AccessRight Full -Force;
$_ = Grant-SmbShareAccess -Name $shareName -AccountName $researcherUserSg -AccessRight Change -Force;

Write-Output "SMB share access for '$shareName' share:"
Get-SmbShareAccess -Name $shareName | Format-List

Write-Output "Setting ACL rules for folder '$sharePath'"
# Remove all existing ACL rules on the dataserver folder backing the share
$acl = Get-Acl $sharePath;
$_ = ($acl.Access | ForEach-Object{$acl.RemoveAccessRule($_)});
## Set the permissions we want explicitly on the dataserver folder backing the share
$serverAdminAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($serverAdminSg, 
                            "Full", "ContainerInherit, ObjectInherit", "None", "Allow");
$researchUserAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($researcherUserSg, 
                            "Modify", "ContainerInherit, ObjectInherit", "None", "Allow");
$_ = $acl.Setaccessrule($serverAdminAccessRule);     
$_ = $acl.Setaccessrule($researchUserAccessRule);
$_ = (Set-Acl $sharePath $acl);

Write-Output "ACL access rules for '$sharePath' folder:"
Get-Acl $sharePath | Format-List

