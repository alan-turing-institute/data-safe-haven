# Enable the RDS-Gateway feature
$null = Add-WindowsFeature -Name RDS-Gateway -IncludeAllSubFeature -ErrorAction Stop

# Note that RemoteDesktopServices is installed by `Add-WindowsFeature -Name RDS-Gateway`
Import-Module RemoteDesktop -ErrorAction Stop
Import-Module RemoteDesktopServices -ErrorAction Stop

# Configure attached disk drives
# ------------------------------
Stop-Service ShellHWDetection
# Initialise disks
Write-Output "Initialising data drives..."
$null = Get-Disk | Where-Object { $_.PartitionStyle -eq "raw" } | ForEach-Object { Initialize-Disk -PartitionStyle GPT -Number $_.Number }
# Check that all disks are correctly partitioned
Write-Output "Checking drive partitioning..."
$DataDisks = Get-Disk | Where-Object { $_.Model -ne "Virtual HD" } | Sort -Property Number  # This excludes the OS and temp disks
foreach ($DataDisk in $DataDisks) {
    $existingPartitions = @(Get-Partition -DiskNumber $DataDisk.Number | Where-Object { $_.Type -eq "Basic" })  # This selects normal partitions that are not system-reserved
    # Remove all basic partitions if there is not exactly one
    if ($existingPartitions.Count -gt 1) {
        Write-Output " [ ] Found $($existingPartitions.Count) partitions on disk $($DataDisk.DiskNumber) but expected 1! Removing all of them."
        $existingPartitions | ForEach-Object { Remove-Partition -DiskNumber $DataDisk.DiskNumber -PartitionNumber $_.PartitionNumber -Confirm:$false }
    }
    # Remove any non-lettered partitions
    $existingPartition = @(Get-Partition -DiskNumber $DataDisk.Number | Where-Object { $_.Type -eq "Basic" })[0]
    if ($existingPartition -and (-not $existingPartition.DriveLetter)) {
        Write-Output "Removing non-lettered partition $($existingPartition.PartitionNumber) from disk $($DataDisk.DiskNumber)!"
        Remove-Partition -DiskNumber $DataDisk.DiskNumber -PartitionNumber $existingPartition.PartitionNumber -Confirm:$false
    }
    # Create a new partition if one does not exist
    $existingPartition = @(Get-Partition -DiskNumber $DataDisk.Number | Where-Object { $_.Type -eq "Basic" })[0]
    if ($existingPartition) {
        Write-Output " [o] Partition $($existingPartition.PartitionNumber) of disk $($DataDisk.DiskNumber) is mounted at drive letter '$($existingPartition.DriveLetter)'"
    } else {
        $LUN = $(Get-WmiObject Win32_DiskDrive | Where-Object { $_.Index -eq $DataDisk.Number }).SCSILogicalUnit
        $Label = "DATA-$LUN"
        $Partition = New-Partition -DiskNumber $DataDisk.Number -UseMaximumSize -AssignDriveLetter
        Write-Output " [o] Formatting partition $($Partition.PartitionNumber) of disk $($DataDisk.Number) with label '$Label' at drive letter '$($Partition.DriveLetter)'"
        $null = Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel $Label -Confirm:$false
    }
}
Start-Service ShellHWDetection
# Construct map of folders to disk labels
$DiskLabelMap = @{
    "AppFileShares" = "DATA-0"
}


# Remove any old RDS settings
# ---------------------------
Write-Output "Removing any old RDS settings..."
foreach ($collection in $(Get-RDSessionCollection -ErrorAction SilentlyContinue)) {
    Write-Output "... removing existing RDSessionCollection: '$($collection.CollectionName)'"
    Remove-RDSessionCollection -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName $collection.CollectionName -Force -ErrorAction SilentlyContinue
}
foreach ($server in $(Get-RDServer -ErrorAction SilentlyContinue)) {
    Write-Output "... removing existing RDServer: '$($server.Server)'"
    foreach ($role in $server.Roles) {
        Remove-RDServer -ConnectionBroker "<rdsGatewayVmFqdn>" -Server $server.Server -Role $role -Force -ErrorAction SilentlyContinue
    }
}
foreach ($policyName in $(Get-Item "RDS:\GatewayServer\RAP" -ErrorAction SilentlyContinue | Get-ChildItem | ForEach-Object { $_.Name })) {
    Write-Output "... removing existing RAP policy '$policyName'"
    Remove-Item "RDS:\GatewayServer\RAP\${policyName}" -Recurse -ErrorAction SilentlyContinue
}
$null = Set-Item "RDS:\GatewayServer\CentralCAPEnabled" -Value 0 -ErrorAction SilentlyContinue
foreach ($policyName in $(Get-Item "RDS:\GatewayServer\CAP" -ErrorAction SilentlyContinue | Get-ChildItem | ForEach-Object { $_.Name })) {
    Write-Output "... removing existing CAP policy '$policyName'"
    Remove-Item "RDS:\GatewayServer\CAP\${policyName}" -Recurse -ErrorAction SilentlyContinue
}


# Create RDS Environment
# ----------------------
Write-Output "Creating RDS Environment..."
try {
    New-RDSessionDeployment -ConnectionBroker "<rdsGatewayVmFqdn>" -WebAccessServer "<rdsGatewayVmFqdn>" -SessionHost @("<rdsAppSessionHostFqdn>") -ErrorAction Stop
    # Setup licensing server
    Add-RDServer -ConnectionBroker "<rdsGatewayVmFqdn>" -Server "<rdsGatewayVmFqdn>" -Role RDS-LICENSING -ErrorAction Stop
    Set-RDLicenseConfiguration -ConnectionBroker "<rdsGatewayVmFqdn>" -LicenseServer "<rdsGatewayVmFqdn>" -Mode PerUser -Force -ErrorAction Stop
    # Setup gateway server
    Add-RDServer -ConnectionBroker "<rdsGatewayVmFqdn>" -Server "<rdsGatewayVmFqdn>" -Role RDS-GATEWAY -GatewayExternalFqdn "<sreDomain>" -ErrorAction Stop
    Set-RDWorkspace -ConnectionBroker "<rdsGatewayVmFqdn>" -Name "Safe Haven Applications"
    Write-Output " [o] RDS environment configuration update succeeded"
} catch {
    Write-Output " [x] RDS environment configuration update failed!"
    throw
}


# Create collections
# ------------------
foreach ($rdsConfiguration in @(, @("Applications", "<rdsAppSessionHostFqdn>", "<researchUserSgName>", "AppFileShares"))) {
    $collectionName, $sessionHost, $userGroup, $shareName = $rdsConfiguration
    $sharePath = Join-Path "$((Get-Volume | Where-Object { $_.FileSystemLabel -eq $DiskLabelMap[$shareName] }).DriveLetter):" $shareName

    # Setup user profile disk shares
    Write-Output "Creating user profile disk shares..."
    $null = New-Item -ItemType Directory -Force -Path $sharePath
    $sessionHostComputerName = $sessionHost.Split(".")[0]
    if ($null -eq $(Get-SmbShare | Where-Object -Property Path -EQ $sharePath)) {
        $null = New-SmbShare -Path $sharePath -Name $shareName -FullAccess "<shmNetbiosName>\<rdsGatewayVmName>$", "<shmNetbiosName>\${sessionHostComputerName}$", "<shmNetbiosName>\Domain Admins"
    }

    # Create collections
    Write-Output "Creating '$collectionName' collection..."
    try {
        $null = New-RDSessionCollection -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "$collectionName" -SessionHost "$sessionHost" -ErrorAction Stop
        $null = Set-RDSessionCollectionConfiguration -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "$collectionName" -UserGroup "<shmNetbiosName>\$userGroup" -ClientPrinterRedirected $false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ErrorAction Stop
        $null = Set-RDSessionCollectionConfiguration -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "$collectionName" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath "\\<rdsGatewayVmName>\$shareName" -ErrorAction Stop
        Write-Output " [o] Creating '$collectionName' collection succeeded"
    } catch {
        Write-Output " [x] Creating '$collectionName' collection failed!"
        throw
    }
}


# Create applications
# -------------------
Write-Output "Registering applications..."
Get-RDRemoteApp | Remove-RDRemoteApp -Force -ErrorAction SilentlyContinue
try {
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "Applications" -DisplayName "DSVM Main (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-v <dsvmInitialIpAddress>" -ErrorAction Stop
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "Applications" -DisplayName "DSVM Other (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -ErrorAction Stop
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "Applications" -DisplayName "GitLab" -FilePath "C:\Program Files\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://<gitlabIpAddress>" -ErrorAction Stop
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "Applications" -DisplayName "HackMD" -FilePath "C:\Program Files\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://<hackmdIpAddress>" -ErrorAction Stop
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "Applications" -DisplayName "DSVM Main (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-ssh <dsvmInitialIpAddress>" -ErrorAction Stop
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "Applications" -DisplayName "DSVM Other (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -ErrorAction Stop
    Write-Output " [o] Registering applications succeeded"
} catch {
    Write-Output " [x] Registering applications failed!"
    throw
}


# Update server configuration
# ---------------------------
Write-Output "Updating server configuration..."
try {
    Get-Process ServerManager -ErrorAction SilentlyContinue | Stop-Process -Force
    foreach ($targetDirectory in @("C:\Users\<domainAdminUsername>\AppData\Roaming\Microsoft\Windows\ServerManager",
                                   "C:\Users\<domainAdminUsername>.<shmNetbiosName>\AppData\Roaming\Microsoft\Windows\ServerManager")) {
        $null = New-Item -ItemType Directory -Path $targetDirectory -Force -ErrorAction Stop
        Copy-Item -Path "<remoteUploadDir>\ServerList.xml" -Destination "$targetDirectory\ServerList.xml" -Force -ErrorAction Stop
    }
    Start-Process -FilePath $env:SystemRoot\System32\ServerManager.exe -WindowStyle Maximized -ErrorAction Stop
    Write-Output " [o] Server configuration update succeeded"
} catch {
    Write-Output " [x] Server configuration update failed!"
    throw
}


# Install RDS webclient
# ---------------------
Write-Output "Installing RDS webclient..."
try {
    Install-RDWebClientPackage -ErrorAction Stop
    # We cannot publish the WebClient here as we have not yet setup a broker certificate.
    # We do not configure the broker cert here as our RDS SSL certificates are set up in a
    # separate script to support easy renewal. This means that, until the SSL certificate
    # installation script is run for the first time, the RDS WebClient URL will return a 404 page.
    Write-Output " [o] RDS webclient installation succeeded"
} catch {
    Write-Output " [x] RDS webclient installation failed!"
    throw
}


# Remove the requirement for the /RDWeb/webclient/ suffix by setting up a redirect in IIS
# ---------------------------------------------------------------------------------------
Write-Output "Setting up IIS redirect..."
try {
    Set-WebConfiguration system.webServer/httpRedirect "IIS:\sites\Default Web Site" -Value @{enabled = "true"; destination = "/RDWeb/webclient/"; httpResponseStatus = "Permanent" } -ErrorAction Stop
    Write-Output " [o] IIS redirection succeeded"
} catch {
    Write-Output " [x] IIS redirection failed!"
    throw
}
