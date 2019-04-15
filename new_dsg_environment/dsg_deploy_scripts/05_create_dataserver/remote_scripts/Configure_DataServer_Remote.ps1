# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $configJson
)
# For some reason, passing a JSON string as the -Parameter value for Invoke-AzVMRunCommand
# results in the double quotes in the JSON string being stripped in transit
# Escaping these with a single backslash retains the double quotes but the transferred
# string is truncated. Escaping these with backticks still results in the double quotes
# being stripped in transit, but we can then replace the backticks with double quotes 
# at this end to recover a valid JSON string.
$config =  ($configJson.Replace("``","`"") | ConvertFrom-Json)

# Set language and time-zone
Write-Output "Setting system locale"
Set-WinHomeLocation -GeoId 0xf2
Set-TimeZone -Name "GMT Standard Time"
Set-WinSystemLocale en-GB
Set-Culture en-GB
Set-WinUserLanguageList -LanguageList (New-WinUserLanguageList -Language en-GB) -Force

#Format data drive
Stop-Service ShellHWDetection

$rawDisks = Get-Disk |  Where {$_.PartitionStyle -eq 'raw'} | Sort -Property Number
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
$researcherUserSg = ($config.shm.domain.netbiosName + "\" + $config.dsg.domain.securityGroups.researchUsers.name) 
$serverAdminSg = ($config.dsg.domain.netbiosName + "\" + $config.dsg.domain.securityGroups.serverAdmins.name)
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

Get-SmbShareAccess -Name $shareName | Format-Table

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

Get-Acl $sharePath | Format-List

