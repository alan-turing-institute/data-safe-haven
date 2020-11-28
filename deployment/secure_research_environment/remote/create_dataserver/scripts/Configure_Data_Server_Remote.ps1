param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "SRE Netbios name")]
    [string]$sreNetbiosName,
    [Parameter(Position = 1, Mandatory = $true, HelpMessage = "SHM Netbios name")]
    [string]$shmNetbiosName,
    [Parameter(Position = 2, Mandatory = $true, HelpMessage = "User which enables the SMB share to be mounted locally")]
    [string]$dataMountUser,
    [Parameter(Position = 3, Mandatory = $true, HelpMessage = "Security group name for research users")]
    [string]$researcherUserSgName,
    [Parameter(Position = 4, Mandatory = $true, HelpMessage = "Security group name for server admins")]
    [string]$serverAdminSgName
)


# Initialise the data drives
# --------------------------
Write-Output "Initialising data drives..."
Stop-Service ShellHWDetection
$null = Get-Disk | Where-Object { $_.PartitionStyle -eq "raw" } | ForEach-Object { Initialize-Disk -PartitionStyle GPT -Number $_.Number }


# Check that all disks are correctly partitioned
# ----------------------------------------------
Write-Output "Checking drive partitioning..."
$dataDisks = Get-Disk | Where-Object { $_.Model -ne "Virtual HD" } | Sort -Property Number  # This excludes the OS and temp disks
foreach ($disk in $dataDisks) {
    $existingPartition = Get-Partition -DiskNumber $disk.Number | Where-Object { $_.Type -eq "Basic" }  # This selects normal partitions that are not system-reserved
    if ($existingPartition.DriveLetter) {
        Write-Output " [o] Partition $($existingPartition.PartitionNumber) of disk $($disk.DiskNumber) is mounted at drive letter '$($existingPartition.DriveLetter)'"
    } else {
        if ($existingPartition.PartitionNumber) {
            Write-Output "Removing non-lettered partition $($existingPartition.PartitionNumber) from disk $($disk.DiskNumber)!"
            Remove-Partition -DiskNumber $disk.DiskNumber -PartitionNumber $existingPartition.PartitionNumber -Confirm:$false
        }
        $LUN = $(Get-WmiObject Win32_DiskDrive | Where-Object { $_.Index -eq $disk.Number }).SCSILogicalUnit
        $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
        $label = "DATA-$LUN"
        Write-Output " [o] Formatting partition $($partition.PartitionNumber) of disk $($disk.Number) with label '$label' at drive letter '$($partition.DriveLetter)'"
        $null = Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $label -Confirm:$false
    }
}
Start-Service ShellHWDetection


# Get map of folders to disk location since do not know which disk letter will be assigned in advance
# ---------------------------------------------------------------------------------------------------
$smbShareMap = @{
    "Ingress" = "$((Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq 'DATA-0' }).DeviceId)\Ingress"
    "Shared"  = "$((Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq 'DATA-1' }).DeviceId)\Shared"
    "Egress"  = "$((Get-WmiObject Win32_LogicalDisk | Where-Object { $_.VolumeName -eq 'DATA-2' }).DeviceId)\Egress"
}


# Setup disk shares
# -----------------
Write-Output "Configuring disk shares..."
foreach ($shareName in @("Ingress", "Shared", "Egress")) {
    $sharePath = $smbShareMap[$shareName]
    Write-Output " [ ] Creating SMB data share '$shareName' at '$sharePath'..."
    if (Get-SmbShare | Where-Object { $_.Name -eq "$shareName" }) {
        Write-Output " [o] SMB share '$shareName' already exists"
    } else {
        # Create folder if it does not exist
        if (-not (Test-Path -Path $sharePath)) {
            $null = New-Item -ItemType directory -Path $sharePath
        }
        # Create SMB share
        $null = New-SmbShare -Path $sharePath -Name $shareName -ErrorAction:Continue
        if ($?) {
            Write-Output " [o] Successfully created SMB share '$shareName'"
        } else {
            Write-Output " [x] Failed to create SMB share '$shareName'"
        }
    }
}


# Set SMB and ACL access rules
# ----------------------------
$dataMountDomainUser = "$shmNetbiosName\$dataMountUser"
$researcherUserSg = "$shmNetbiosName\$researcherUserSgName"
$serverAdminSg = "$shmNetbiosName\$serverAdminSgName"
foreach ($pathAccessTuple in (("Ingress", "Read", "Read"), ("Shared", "Change", "Modify"), ("Egress", "Full", "Full"))) {
    $shareName, $smbAccessRight, $aclAccessRight = $pathAccessTuple

    Write-Output "Setting SMB share access for '$shareName' share..."
    # Revoke all access for our security groups and the "Everyone" group to ensure only the permissions we set explicitly apply
    $null = Revoke-SmbShareAccess -Name $shareName -AccountName $dataMountDomainUser -Force -ErrorAction:Continue
    $null = Revoke-SmbShareAccess -Name $shareName -AccountName $researcherUserSg -Force -ErrorAction:Continue
    $null = Revoke-SmbShareAccess -Name $shareName -AccountName $serverAdminSg -Force -ErrorAction:Continue
    $null = Revoke-SmbShareAccess -Name $shareName -AccountName Everyone -Force -ErrorAction:Continue
    # Explicitly set the permissions we want on the share
    $null = Grant-SmbShareAccess -Name $shareName -AccountName $dataMountDomainUser -AccessRight $smbAccessRight -Force
    $null = Grant-SmbShareAccess -Name $shareName -AccountName $researcherUserSg -AccessRight $smbAccessRight -Force
    $null = Grant-SmbShareAccess -Name $shareName -AccountName $serverAdminSg -AccessRight Full -Force

    $sharePath = $smbShareMap[$shareName]
    Write-Output "Setting ACL rules for folder '$sharePath'"
    # Remove all existing ACL rules on the folder backing the share
    $acl = Get-Acl $sharePath
    $null = $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
    # Explicitly set the permissions we want on the folder backing the share
    # https://docs.microsoft.com/en-us/dotnet/api/system.security.accesscontrol.filesystemrights?view=netframework-4.8
    $serverAdminAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($serverAdminSg, "Full", "ContainerInherit, ObjectInherit", "None", "Allow");
    $researchUserAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($researcherUserSg, $aclAccessRight, "ContainerInherit, ObjectInherit", "None", "Allow");
    $dataMountAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($dataMountDomainUser, $aclAccessRight, "ContainerInherit, ObjectInherit", "None", "Allow");
    $null = $acl.SetAccessRule($serverAdminAccessRule)
    $null = $acl.SetAccessRule($researchUserAccessRule)
    $null = $acl.SetAccessRule($dataMountAccessRule)
    $null = (Set-Acl $sharePath $acl)

    # Print current permissions and access rules
    $rules = (Get-Acl $sharePath).Access | Select-Object -Property IdentityReference, FileSystemRights
    Write-Output "ACL access rules for '$sharePath' folder are currently:`n$($rules | Out-String)"
}
