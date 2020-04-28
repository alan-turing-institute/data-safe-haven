Import-Module RemoteDesktop


# Initialise the data drives
# --------------------------
Write-Output "Initialising data drives..."
Stop-Service ShellHWDetection
$CandidateRawDisks = Get-Disk | Where-Object {$_.PartitionStyle -eq 'raw'} | Sort -Property Number
foreach ($RawDisk in $CandidateRawDisks) {
    $LUN = (Get-WmiObject Win32_DiskDrive | Where-Object index -eq $RawDisk.Number | Select-Object SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    $_ = Initialize-Disk -PartitionStyle GPT -Number $RawDisk.Number
    $Partition = New-Partition -DiskNumber $RawDisk.Number -UseMaximumSize -AssignDriveLetter
    $_ = Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel "DATA-$LUN" -Confirm:$false
}
Start-Service ShellHWDetection


# Setup user profile disk shares
# ------------------------------
Write-Output "Creating user profile disk shares..."
foreach ($sharePath in ("F:\AppFileShares", "G:\RDPFileShares", "H:\ReviewFileShares")) {
    $_ = New-Item -ItemType Directory -Force -Path $sharePath
    if($null -eq $(Get-SmbShare | Where-Object -Property Path -eq $sharePath)) {
        New-SmbShare -Path $sharePath -Name $sharePath.Split("\")[1] -FullAccess "<shmNetbiosName>\<rdsGatewayVmName>$","<shmNetbiosName>\<rdsSh1VmName>$","<shmNetbiosName>\<rdsSh2VmName>$","<shmNetbiosName>\<rdsSh3VmName>$","<shmNetbiosName>\Domain Admins"
    }
}


# Remove any old RDS settings
# ---------------------------
foreach ($collection in $(Get-RDSessionCollection -ErrorAction SilentlyContinue)) {
    Write-Output "Removing existing RDSessionCollection: '$collection.CollectionName' (and associated apps)"
    Remove-RDSessionCollection -CollectionName $collection.CollectionName -Force -ErrorAction SilentlyContinue
}
foreach ($server in $(Get-RDServer -ErrorAction SilentlyContinue)) {
    Write-Output "Removing existing RDServer: '$($server.Server)'"
    foreach ($role in $server.Roles) {
        Remove-RDServer -Server $server.Server -Role $role -Force -ErrorAction SilentlyContinue
    }
}


# Create RDS Environment
# ----------------------
Write-Output "Creating RDS Environment..."
New-RDSessionDeployment -ConnectionBroker "<rdsGatewayVmFqdn>" -WebAccessServer "<rdsGatewayVmFqdn>" -SessionHost @("<rdsSh1VmFqdn>", "<rdsSh2VmFqdn>", "<rdsSh3VmFqdn>")
Add-RDServer -Server <rdsGatewayVmFqdn> -Role RDS-LICENSING -ConnectionBroker <rdsGatewayVmFqdn>
Set-RDLicenseConfiguration -LicenseServer <rdsGatewayVmFqdn> -Mode PerUser -ConnectionBroker <rdsGatewayVmFqdn> -Force
Add-WindowsFeature -Name RDS-Gateway -IncludeAllSubFeature
Add-RDServer -Server <rdsGatewayVmFqdn> -Role RDS-GATEWAY -ConnectionBroker <rdsGatewayVmFqdn> -GatewayExternalFqdn $sreFqdn


# Create collections
# ------------------
$collectionName = "Remote Applications"
Write-Output "Creating '$collectionName' collection..."
New-RDSessionCollection -CollectionName "$collectionName" -SessionHost <rdsSh1VmFqdn> -ConnectionBroker <rdsGatewayVmFqdn>
Set-RDSessionCollectionConfiguration -CollectionName "$collectionName" -UserGroup "<shmNetbiosName>\<researchUserSgName>" -ClientPrinterRedirected $false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker <rdsGatewayVmFqdn>
Set-RDSessionCollectionConfiguration -CollectionName "$collectionName" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\<rdsGatewayVmName>\AppFileShares -ConnectionBroker <rdsGatewayVmFqdn>

$collectionName = "Presentation Server"
Write-Output "Creating '$collectionName' collection..."
New-RDSessionCollection -CollectionName "$collectionName" -SessionHost <rdsSh2VmFqdn> -ConnectionBroker <rdsGatewayVmFqdn>
Set-RDSessionCollectionConfiguration -CollectionName "$collectionName" -UserGroup "<shmNetbiosName>\<researchUserSgName>" -ClientPrinterRedirected $false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker <rdsGatewayVmFqdn>
Set-RDSessionCollectionConfiguration -CollectionName "$collectionName" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\<rdsGatewayVmName>\RDPFileShares -ConnectionBroker <rdsGatewayVmFqdn>

$collectionName = "Review"
Write-Output "Creating '$collectionName' collection..."
New-RDSessionCollection -CollectionName "$collectionName" -SessionHost <rdsSh3VmFqdn> -ConnectionBroker <rdsGatewayVmFqdn>
Set-RDSessionCollectionConfiguration -CollectionName "$collectionName" -UserGroup "<shmNetbiosName>\<reviewUserSgName>" -ClientPrinterRedirected $false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker <rdsGatewayVmFqdn>
Set-RDSessionCollectionConfiguration -CollectionName "$collectionName" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\<rdsGatewayVmName>\ReviewFileShares -ConnectionBroker <rdsGatewayVmFqdn>


# Create applications
# -------------------
Write-Output "Creating applications..."
New-RDRemoteApp -Alias "mstsc (1)" -DisplayName "DSVM Main (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-v <dataSubnetIpPrefix>.160" -CollectionName "Remote Applications" -ConnectionBroker <rdsGatewayVmFqdn>
New-RDRemoteApp -Alias "putty (1)" -DisplayName "DSVM Main (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-ssh <dataSubnetIpPrefix>.160" -CollectionName "Remote Applications" -ConnectionBroker <rdsGatewayVmFqdn>
New-RDRemoteApp -Alias "mstsc (2)" -DisplayName "DSVM Other (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker <rdsGatewayVmFqdn>
New-RDRemoteApp -Alias "putty (2)" -DisplayName "DSVM Other (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker <rdsGatewayVmFqdn>
New-RDRemoteApp -Alias WinSCP -DisplayName "File Transfer" -FilePath "C:\Program Files (x86)\WinSCP\WinSCP.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker <rdsGatewayVmFqdn>
New-RDRemoteApp -Alias "chrome (1)" -DisplayName "GitLab" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://<dataSubnetIpPrefix>.151" -CollectionName "Remote Applications" -ConnectionBroker <rdsGatewayVmFqdn>
New-RDRemoteApp -Alias "chrome (2)" -DisplayName "HackMD" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://<dataSubnetIpPrefix>.152:3000" -CollectionName "Remote Applications" -ConnectionBroker <rdsGatewayVmFqdn>
New-RDRemoteApp -Alias "chrome (3)" -DisplayName "GitLab Review" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://<airlockSubnetIpPrefix>.151" -CollectionName "Review" -ConnectionBroker <rdsGatewayVmFqdn>


# Update server configuration
# ---------------------------
Write-Output "Updating server configuration..."
Get-Process ServerManager -ErrorAction SilentlyContinue | Stop-Process -Force
foreach ($targetDirectory in @("C:\Users\<shmDcAdminUsername>\AppData\Roaming\Microsoft\Windows\ServerManager",
                               "C:\Users\<shmDcAdminUsername>.<shmNetbiosName>\AppData\Roaming\Microsoft\Windows\ServerManager")) {
    $_ = New-Item -ItemType Directory -Force -Path $targetDirectory
    Copy-Item -Path "<remoteUploadDir>\ServerList.xml" -Destination "$targetDirectory\ServerList.xml" -Force
}
Start-Process -FilePath $env:SystemRoot\System32\ServerManager.exe -WindowStyle Maximized
if ($?) {
    Write-Output " [o] Server configuration update succeeded"
} else {
    Write-Output " [x] Server configuration update failed!"
}


# Install RDS webclient
# ---------------------
Write-Output "Installing RDS webclient..."
Install-RDWebClientPackage
if ($?) {
    Write-Output " [o] RDS webclient installation succeeded"
} else {
    Write-Output " [x] RDS webclient installation failed!"
}


# Remove the requirement for the /RDWeb/webclient/ suffix by setting up a redirect in IIS
# ---------------------------------------------------------------------------------------
Set-WebConfiguration system.webServer/httpRedirect "IIS:\sites\Default Web Site" -Value @{enabled="true";destination="/RDWeb/webclient/";httpResponseStatus="Permanent"}
