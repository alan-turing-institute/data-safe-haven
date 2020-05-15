Import-Module RemoteDesktop


# Initialise the data drives
# --------------------------
Write-Output "Initialising data drives..."
Stop-Service ShellHWDetection
$CandidateRawDisks = Get-Disk | Where-Object {$_.PartitionStyle -eq 'raw'} | Sort -Property Number
foreach ($RawDisk in $CandidateRawDisks) {
    Write-Output "Configuring disk $($RawDisk.Number)"
    $LUN = (Get-WmiObject Win32_DiskDrive | Where-Object index -eq $RawDisk.Number | Select-Object SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    $_ = Initialize-Disk -PartitionStyle GPT -Number $RawDisk.Number
    $Partition = New-Partition -DiskNumber $RawDisk.Number -UseMaximumSize -AssignDriveLetter
    $_ = Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel "DATA-$LUN" -Confirm:$false
}
Start-Service ShellHWDetection


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


# Create RDS Environment
# ----------------------
Write-Output "Creating RDS Environment..."
try {
    # Setup licensing server
    New-RDSessionDeployment -ConnectionBroker "<rdsGatewayVmFqdn>" -WebAccessServer "<rdsGatewayVmFqdn>" -SessionHost @("<rdsSh1VmFqdn>", "<rdsSh2VmFqdn>", "<rdsSh3VmFqdn>") -ErrorAction Stop
    Add-RDServer -ConnectionBroker "<rdsGatewayVmFqdn>" -Server "<rdsGatewayVmFqdn>" -Role RDS-LICENSING  -ErrorAction Stop
    Set-RDLicenseConfiguration -ConnectionBroker "<rdsGatewayVmFqdn>" -LicenseServer "<rdsGatewayVmFqdn>" -Mode PerUser  -Force -ErrorAction Stop
    # Setup gateway server
    $_ = Add-WindowsFeature -Name RDS-Gateway -IncludeAllSubFeature -ErrorAction Stop
    Add-RDServer -ConnectionBroker "<rdsGatewayVmFqdn>" -Server "<rdsGatewayVmFqdn>" -Role RDS-GATEWAY -GatewayExternalFqdn "<sreFqdn>" -ErrorAction Stop
    Set-RDWorkspace -ConnectionBroker "<rdsGatewayVmFqdn>" -Name "Safe Haven Applications"
    Write-Output " [o] RDS environment configuration update succeeded"
} catch {
    Write-Output " [x] RDS environment configuration update failed!"
    throw
}


# Create collections
# ------------------
$driveLetters = Get-Volume | Where-Object { $_.FileSystemLabel -Like "DATA-[0-9]" } | ForEach-Object { $_.DriveLetter } | Sort
foreach($rdsConfiguration in @(("Applications", "<rdsSh1VmFqdn>", "<researchUserSgName>", "$($driveLetters[0]):\AppFileShares"),
                               ("Windows (Desktop)", "<rdsSh2VmFqdn>", "<researchUserSgName>", "$($driveLetters[1]):\RDPFileShares"),
                               ("Review", "<rdsSh3VmFqdn>", "<reviewUserSgName>", "$($driveLetters[2]):\ReviewFileShares"))) {
    $collectionName, $sessionHost, $userGroup, $sharePath = $rdsConfiguration

    # Setup user profile disk shares
    Write-Output "Creating user profile disk shares..."
    $_ = New-Item -ItemType Directory -Force -Path $sharePath
    $shareName = $sharePath.Split("\")[1]
    $sessionHostComputerName = $sessionHost.Split(".")[0]
    if ($null -eq $(Get-SmbShare | Where-Object -Property Path -eq $sharePath)) {
        $_ = New-SmbShare -Path $sharePath -Name $shareName -FullAccess "<shmNetbiosName>\<rdsGatewayVmName>$","<shmNetbiosName>\${sessionHostComputerName}$","<shmNetbiosName>\Domain Admins"
    }

    # Create collections
    Write-Output "Creating '$collectionName' collection..."
    try {
        $_ = New-RDSessionCollection -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "$collectionName" -SessionHost "$sessionHost" -ErrorAction Stop
        $_ = Set-RDSessionCollectionConfiguration -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "$collectionName" -UserGroup "<shmNetbiosName>\$userGroup" -ClientPrinterRedirected $false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ErrorAction Stop
        $_ = Set-RDSessionCollectionConfiguration -ConnectionBroker "<rdsGatewayVmFqdn>" -CollectionName "$collectionName" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath "\\<rdsGatewayVmName>\$shareName" -ErrorAction Stop
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
    $_ = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -Alias "chrome (1)" -DisplayName "Code Review" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://<airlockSubnetIpPrefix>.151" -CollectionName "Review" -ErrorAction Stop
    $_ = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -Alias "mstsc (1)" -DisplayName "DSVM Main (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-v <dataSubnetIpPrefix>.160" -CollectionName "Applications" -ErrorAction Stop
    $_ = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -Alias "mstsc (2)" -DisplayName "DSVM Other (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CollectionName "Applications" -ErrorAction Stop
    $_ = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -Alias "chrome (2)" -DisplayName "GitLab" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://<dataSubnetIpPrefix>.151" -CollectionName "Applications" -ErrorAction Stop
    $_ = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -Alias "chrome (3)" -DisplayName "HackMD" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://<dataSubnetIpPrefix>.152:3000" -CollectionName "Applications" -ErrorAction Stop
    $_ = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -Alias "putty (1)" -DisplayName "SSH (DSVM Main)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-ssh <dataSubnetIpPrefix>.160" -CollectionName "Applications" -ErrorAction Stop
    $_ = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -Alias "putty (2)" -DisplayName "SSH (DSVM Other)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CollectionName "Applications" -ErrorAction Stop
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
    foreach ($targetDirectory in @("C:\Users\<shmDcAdminUsername>\AppData\Roaming\Microsoft\Windows\ServerManager",
                                   "C:\Users\<shmDcAdminUsername>.<shmNetbiosName>\AppData\Roaming\Microsoft\Windows\ServerManager")) {
        $_ = New-Item -ItemType Directory -Path $targetDirectory -Force -ErrorAction Stop
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
    Write-Output " [o] RDS webclient installation succeeded"
} catch {
    Write-Output " [x] RDS webclient installation failed!"
    throw
}


# Remove the requirement for the /RDWeb/webclient/ suffix by setting up a redirect in IIS
# ---------------------------------------------------------------------------------------
Write-Output "Setting up IIS redirect..."
try {
    Set-WebConfiguration system.webServer/httpRedirect "IIS:\sites\Default Web Site" -Value @{enabled="true";destination="/RDWeb/webclient/";httpResponseStatus="Permanent"} -ErrorAction Stop
    Write-Output " [o] IIS redirection succeeded"
} catch {
    Write-Output " [x] IIS redirection failed!"
    throw
}
