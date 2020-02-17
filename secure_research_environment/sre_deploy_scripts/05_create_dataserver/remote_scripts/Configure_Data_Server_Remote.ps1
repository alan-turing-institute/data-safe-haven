param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "SRE Netbios name")]
  [string]$sreNetbiosName,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "SHM Netbios name")]
  [string]$shmNetbiosName,
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "Security group name for research users")]
  [string]$researcherUserSgName,
  [Parameter(Position=3, Mandatory = $true, HelpMessage = "Security group name for server admins")]
  [string]$serverAdminSgName
)

# LOCALE CODE IS PROGRAMATICALLY INSERTED HERE

# Initialise the data drives
# --------------------------
Write-Host "Initialising data drives..."
Stop-Service ShellHWDetection
$CandidateRawDisks = Get-Disk | Where {$_.PartitionStyle -eq 'raw'} | Sort -Property Number
Foreach ($rawDisk in $CandidateRawDisks) {
    $LUN = (Get-WmiObject Win32_DiskDrive | Where index -eq $rawDisk.Number | Select SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    $disk = Initialize-Disk -PartitionStyle GPT -Number $rawDisk.Number
    $partition = New-Partition -DiskNumber $rawDisk.Number -UseMaximumSize -AssignDriveLetter
    $label = "DATA-$LUN"
    Write-Output ("Formatting partition " + $partition.PartitionNumber + " of raw disk " + $rawDisk.Number + " with label '" + $label + "' at drive letter '" + $partition.DriveLetter + "'")
    $volume = Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $label -Confirm:$false
}
Start-Service ShellHWDetection


# Setup disk shares
# -----------------
Write-Host "Configuring disk shares..."
$shareName = "Data"
$sharePath = (Join-Path "F:" $shareName)
$researcherUserSg = ($shmNetbiosName + "\" + $researcherUserSgName)
$serverAdminSg = ($sreNetbiosName + "\" + $serverAdminSgName)
Write-Host " [ ] Creating SMB data share '$shareName'..."
if (Get-SmbShare | Where-Object {$_.Name -eq "$shareName"}) {
    Write-Host " [o] SMB share '$shareName' already exists"
} else {
    # Create share, being robust to case where share folder already exists
    if(!(Test-Path -Path $sharePath)) {
        $_ = New-Item -ItemType directory -Path $sharePath;
    }
    $_ = New-SmbShare -Path $sharePath -Name $shareName -ErrorAction:Continue;
    if ($?) {
        Write-Host " [o] Completed"
    } else {
        Write-Host " [x] Failed"
    }
}

# Set SMB share access
# --------------------
Write-Host "Setting SMB share access for  '$shareName' share..."
# Revoke all access for our security groups and the "Everyone" group to ensure only the permissions we set explicitly apply
$_ = Revoke-SmbShareAccess -Name $shareName -AccountName $researcherUserSg -Force -ErrorAction:Continue;
$_ = Revoke-SmbShareAccess -Name $shareName -AccountName $serverAdminSg -Force -ErrorAction:Continue;
$_ = Revoke-SmbShareAccess -Name $shareName -AccountName Everyone -Force -ErrorAction:Continue;
# Set the permissions we want explicitly on the share
$_ = Grant-SmbShareAccess -Name $shareName -AccountName $serverAdminSg -AccessRight Full -Force;
$_ = Grant-SmbShareAccess -Name $shareName -AccountName $researcherUserSg -AccessRight Change -Force;
# Print current permissions
Write-Output "SMB share access for '$shareName' share is currently:"
Get-SmbShareAccess -Name $shareName | Format-List


# Set ACL rules
# -------------
Write-Output "Setting ACL rules for folder '$sharePath'"
# Remove all existing ACL rules on the dataserver folder backing the share
$acl = Get-Acl $sharePath;
$_ = ($acl.Access | ForEach-Object{$acl.RemoveAccessRule($_)});
# Set the permissions we want explicitly on the dataserver folder backing the share
$serverAdminAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($serverAdminSg, "Full", "ContainerInherit, ObjectInherit", "None", "Allow");
$researchUserAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($researcherUserSg, "Modify", "ContainerInherit, ObjectInherit", "None", "Allow");
$_ = $acl.Setaccessrule($serverAdminAccessRule);
$_ = $acl.Setaccessrule($researchUserAccessRule);
$_ = (Set-Acl $sharePath $acl);
# Print current access rules
Write-Output "ACL access rules for '$sharePath' folder are currently:"
Get-Acl $sharePath | Format-List

