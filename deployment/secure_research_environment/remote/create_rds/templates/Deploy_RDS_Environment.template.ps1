Import-Module RemoteDesktop
Import-Module RemoteDesktopServices


# Initialise the data drives
# --------------------------
Write-Output "Initialising data drives..."
Stop-Service ShellHWDetection
$CandidateRawDisks = Get-Disk | Where-Object {$_.PartitionStyle -eq 'raw'} | Sort -Property Number
foreach ($RawDisk in $CandidateRawDisks) {
    Write-Output "Configuring disk $($RawDisk.Number)"
    $LUN = (Get-WmiObject Win32_DiskDrive | Where-Object index -eq $RawDisk.Number | Select-Object SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    $null = Initialize-Disk -PartitionStyle GPT -Number $RawDisk.Number
    $Partition = New-Partition -DiskNumber $RawDisk.Number -UseMaximumSize -AssignDriveLetter
    $null = Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel "DATA-$LUN" -Confirm:$false
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
    # Setup licensing server
    New-RDSessionDeployment -ConnectionBroker "<rdsGatewayVmFqdn>" -WebAccessServer "<rdsGatewayVmFqdn>" -SessionHost @("<rdsAppSessionHostFqdn>") -ErrorAction Stop
    Add-RDServer -ConnectionBroker "<rdsGatewayVmFqdn>" -Server "<rdsGatewayVmFqdn>" -Role RDS-LICENSING  -ErrorAction Stop
    Set-RDLicenseConfiguration -ConnectionBroker "<rdsGatewayVmFqdn>" -LicenseServer "<rdsGatewayVmFqdn>" -Mode PerUser  -Force -ErrorAction Stop
    # Setup gateway server
    $null = Add-WindowsFeature -Name RDS-Gateway -IncludeAllSubFeature -ErrorAction Stop
    Add-RDServer -ConnectionBroker "<rdsGatewayVmFqdn>" -Server "<rdsGatewayVmFqdn>" -Role RDS-GATEWAY -GatewayExternalFqdn "<sreDomain>" -ErrorAction Stop
    Set-RDWorkspace -ConnectionBroker "<rdsGatewayVmFqdn>" -Name "Safe Haven Applications"
    Write-Output " [o] RDS environment configuration update succeeded"
} catch {
    Write-Output " [x] RDS environment configuration update failed!"
    throw
}


# Create collections
# ------------------
$driveLetters = Get-Volume | Where-Object { $_.FileSystemLabel -Like "DATA-[0-9]" } | ForEach-Object { $_.DriveLetter } | Sort
foreach ($rdsConfiguration in @(("Applications", "<rdsAppSessionHostFqdn>", "<researchUserSgName>", "$($driveLetters[0]):\AppFileShares"))) {
    $collectionName, $sessionHost, $userGroup, $sharePath = $rdsConfiguration
    if ($collectionName -eq "Windows (Desktop)") { continue }  # do not create links for the Windows desktop as we are preparing to remove this

    # Setup user profile disk shares
    Write-Output "Creating user profile disk shares..."
    $null = New-Item -ItemType Directory -Force -Path $sharePath
    $shareName = $sharePath.Split("\")[1]
    $sessionHostComputerName = $sessionHost.Split(".")[0]
    if ($null -eq $(Get-SmbShare | Where-Object -Property Path -eq $sharePath)) {
        $null = New-SmbShare -Path $sharePath -Name $shareName -FullAccess "<shmNetbiosName>\<rdsGatewayVmName>$","<shmNetbiosName>\${sessionHostComputerName}$","<shmNetbiosName>\Domain Admins"
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
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -DisplayName "Desktop (DSVM Main)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-v <dsvmInitialIpAddress>" -CollectionName "Applications" -ErrorAction Stop
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -DisplayName "Desktop (DSVM Other)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CollectionName "Applications" -ErrorAction Stop
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -DisplayName "GitLab" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://<gitlabIpAddress>" -CollectionName "Applications" -ErrorAction Stop
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -DisplayName "HackMD" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://<hackmdIpAddress>:3000" -CollectionName "Applications" -ErrorAction Stop
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -DisplayName "SSH (DSVM Main)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-ssh <dsvmInitialIpAddress>" -CollectionName "Applications" -ErrorAction Stop
    $null = New-RDRemoteApp -ConnectionBroker "<rdsGatewayVmFqdn>" -DisplayName "SSH (DSVM Other)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CollectionName "Applications" -ErrorAction Stop
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
