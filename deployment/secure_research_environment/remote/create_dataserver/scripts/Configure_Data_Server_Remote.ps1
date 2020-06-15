param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "SRE Netbios name")]
  [string]$sreNetbiosName,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "SHM Netbios name")]
  [string]$shmNetbiosName,
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "User which enables the SMB share to be mounted locally")]
  [string]$dataMountUser,
  [Parameter(Position=3, Mandatory = $true, HelpMessage = "Security group name for research users")]
  [string]$researcherUserSgName,
  [Parameter(Position=4, Mandatory = $true, HelpMessage = "Security group name for server admins")]
  [string]$serverAdminSgName
)


# Initialise the data drives
# --------------------------
Write-Host "Initialising data drives..."
Stop-Service ShellHWDetection
$rawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq "raw" } | Sort -Property Number
foreach ($rawDisk in $rawDisks) {
    $_ = Initialize-Disk -PartitionStyle GPT -Number $rawDisk.Number
}
Start-Service ShellHWDetection


# Check that all disks are correctly partitioned
# ----------------------------------------------
$dataDisks = Get-Disk | Where-Object { $_.Model -ne "Virtual HD" } | Sort -Property Number  # This excludes the OS and temp disks
foreach ($disk in $dataDisks) {
    $existingPartition = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Type -eq "Basic" }  # This selects normal partitions that are not system-reserved
    if (-Not $existingPartition.DriveLetter) {
        Write-Output "Partition '$($existingPartition.PartitionNumber)' on '$($disk.DiskNumber)' has no associated drive letter!"
        if ($existingPartition.PartitionNumber) {
            Write-Output "Removing partition '$($existingPartition.PartitionNumber)' from disk '$($disk.DiskNumber)'"
            Remove-Partition -DiskNumber $disk.DiskNumber -PartitionNumber $existingPartition.PartitionNumber -Confirm:$false
        }
        $LUN = (Get-WmiObject Win32_DiskDrive | Where-Object index -eq $disk.Number | Select-Object SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
        $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
        $label = "DATA-$LUN"
        Write-Host "Formatting partition $($partition.PartitionNumber) of raw disk $($disk.Number) with label '$label' at drive letter '$($partition.DriveLetter)'"
        $_ = Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $label -Confirm:$false
    }
}


# Setup disk shares
# -----------------
Write-Host "Configuring disk shares..."
foreach ($namePathPair in (("Ingress", "F:\Ingress"),
                           ("Shared", "G:\Shared"),
                           ("Egress", "H:\Egress"))) {
    $shareName, $sharePath = $namePathPair
    $dataMountDomainUser = "$shmNetbiosName\$dataMountUser"
    $researcherUserSg = "$shmNetbiosName\$researcherUserSgName"
    $serverAdminSg = "$shmNetbiosName\$serverAdminSgName"
    Write-Host " [ ] Creating SMB data share '$shareName'..."
    if (Get-SmbShare | Where-Object { $_.Name -eq "$shareName" }) {
        Write-Host " [o] SMB share '$shareName' already exists"
    } else {
        # Create share, being robust to case where share folder already exists
        if (-Not (Test-Path -Path $sharePath)) {
            $_ = New-Item -ItemType directory -Path $sharePath
        }
        $_ = New-SmbShare -Path $sharePath -Name $shareName -ErrorAction:Continue
        if ($?) {
            Write-Host " [o] Completed"
        } else {
            Write-Host " [x] Failed"
        }
    }
}


# Set SMB share access
# --------------------
foreach ($nameAccessPair in (("Ingress", "Read"), ("Shared", "Change"), ("Egress", "Full"))) {
    $shareName, $accessRight = $nameAccessPair
    Write-Host "Setting SMB share access for '$shareName' share..."
    # Revoke all access for our security groups and the "Everyone" group to ensure only the permissions we set explicitly apply
    Write-Host "dataMountDomainUser: '$dataMountDomainUser'"
    $_ = Revoke-SmbShareAccess -Name $shareName -AccountName $serverAdminSg -Force -ErrorAction:Continue
    $_ = Revoke-SmbShareAccess -Name $shareName -AccountName $researcherUserSg -Force -ErrorAction:Continue
    $_ = Revoke-SmbShareAccess -Name $shareName -AccountName $dataMountDomainUser -Force -ErrorAction:Continue
    $_ = Revoke-SmbShareAccess -Name $shareName -AccountName Everyone -Force -ErrorAction:Continue
    # Set the permissions we want explicitly on the share
    $_ = Grant-SmbShareAccess -Name $shareName -AccountName $serverAdminSg -AccessRight Full -Force
    $_ = Grant-SmbShareAccess -Name $shareName -AccountName $researcherUserSg -AccessRight $accessRight -Force
    $_ = Grant-SmbShareAccess -Name $shareName -AccountName $dataMountDomainUser -AccessRight $accessRight -Force
    # Print current permissions
    Write-Host "SMB share access for '$shareName' share is currently:"
    Get-SmbShareAccess -Name $shareName | Format-List
}


# Set ACL rules using the rights listed here: https://docs.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.filesystemrights?view=netframework-4.8
# ------------------------------------------------------------------------------------------------------------------------------------------------------------
foreach ($pathAccessPair in (("F:\Ingress", "Read"), ("G:\Shared", "Modify"), ("H:\Egress", "Full"))) {
    $sharePath, $accessRight = $pathAccessPair
    Write-Host "Setting ACL rules for folder '$sharePath'"
    # Remove all existing ACL rules on the dataserver folder backing the share
    $acl = Get-Acl $sharePath
    $_ = $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
    # Set the permissions we want explicitly on the dataserver folder backing the shares
    $serverAdminAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($serverAdminSg, "Full", "ContainerInherit, ObjectInherit", "None", "Allow");
    $researchUserAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($researcherUserSg, $accessRight, "ContainerInherit, ObjectInherit", "None", "Allow");
    $dataMountAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($dataMountDomainUser, $accessRight, "ContainerInherit, ObjectInherit", "None", "Allow");
    $_ = $acl.SetAccessRule($serverAdminAccessRule)
    $_ = $acl.SetAccessRule($researchUserAccessRule)
    $_ = $acl.SetAccessRule($dataMountAccessRule)
    $_ = (Set-Acl $sharePath $acl)
    # Print current access rules
    Write-Host "ACL access rules for '$sharePath' folder are currently:"
    Get-Acl $sharePath | Format-List
}
