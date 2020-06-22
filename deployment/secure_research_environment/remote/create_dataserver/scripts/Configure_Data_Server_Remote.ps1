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
$CandidateRawDisks = Get-Disk | Where-Object { $_.PartitionStyle -eq "raw" } | Sort -Property Number
foreach ($rawDisk in $CandidateRawDisks) {
    $LUN = (Get-WmiObject Win32_DiskDrive | Where-Object index -eq $rawDisk.Number | Select-Object SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    $null = Initialize-Disk -PartitionStyle GPT -Number $rawDisk.Number
    $partition = New-Partition -DiskNumber $rawDisk.Number -UseMaximumSize -AssignDriveLetter
    $label = "DATA-$LUN"
    Write-Host "Formatting partition $($partition.PartitionNumber) of raw disk $($rawDisk.Number) with label '$label' at drive letter '$($partition.DriveLetter)'"
    $null = Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $label -Confirm:$false
}
Start-Service ShellHWDetection


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
            $null = New-Item -ItemType directory -Path $sharePath
        }
        $null = New-SmbShare -Path $sharePath -Name $shareName -ErrorAction:Continue
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
    $null = Revoke-SmbShareAccess -Name $shareName -AccountName $serverAdminSg -Force -ErrorAction:Continue
    $null = Revoke-SmbShareAccess -Name $shareName -AccountName $researcherUserSg -Force -ErrorAction:Continue
    $null = Revoke-SmbShareAccess -Name $shareName -AccountName $dataMountDomainUser -Force -ErrorAction:Continue
    $null = Revoke-SmbShareAccess -Name $shareName -AccountName Everyone -Force -ErrorAction:Continue
    # Set the permissions we want explicitly on the share
    $null = Grant-SmbShareAccess -Name $shareName -AccountName $serverAdminSg -AccessRight Full -Force
    $null = Grant-SmbShareAccess -Name $shareName -AccountName $researcherUserSg -AccessRight $accessRight -Force
    $null = Grant-SmbShareAccess -Name $shareName -AccountName $dataMountDomainUser -AccessRight $accessRight -Force
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
    $null = $acl.Access | ForEach-Object { $acl.RemoveAccessRule($_) }
    # Set the permissions we want explicitly on the dataserver folder backing the shares
    $serverAdminAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($serverAdminSg, "Full", "ContainerInherit, ObjectInherit", "None", "Allow");
    $researchUserAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($researcherUserSg, $accessRight, "ContainerInherit, ObjectInherit", "None", "Allow");
    $dataMountAccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($dataMountDomainUser, $accessRight, "ContainerInherit, ObjectInherit", "None", "Allow");
    $null = $acl.SetAccessRule($serverAdminAccessRule)
    $null = $acl.SetAccessRule($researchUserAccessRule)
    $null = $acl.SetAccessRule($dataMountAccessRule)
    $null = (Set-Acl $sharePath $acl)
    # Print current access rules
    $rules = (Get-Acl $sharePath).Access | Select-Object -Property IdentityReference, FileSystemRights
    Write-Host "ACL access rules for '$sharePath' folder are currently:`n$($rules | Out-String)"
}
