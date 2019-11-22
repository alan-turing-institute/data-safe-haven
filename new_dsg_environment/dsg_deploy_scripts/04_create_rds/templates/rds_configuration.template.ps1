Import-Module RemoteDesktop


# Initialise the data drives
# --------------------------
Write-Host -ForegroundColor Cyan "Initialising data drives..."
Stop-Service ShellHWDetection
`$CandidateRawDisks = Get-Disk | Where {`$_.PartitionStyle -eq 'raw'} | Sort -Property Number
Foreach (`$RawDisk in `$CandidateRawDisks) {
    `$LUN = (Get-WmiObject Win32_DiskDrive | Where index -eq `$RawDisk.Number | Select SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    `$Disk = Initialize-Disk -PartitionStyle GPT -Number `$RawDisk.Number
    `$Partition = New-Partition -DiskNumber `$RawDisk.Number -UseMaximumSize -AssignDriveLetter
    `$Volume = Format-Volume -Partition `$Partition -FileSystem NTFS -NewFileSystemLabel "DATA-`$LUN" -Confirm:`$false
}
Start-Service ShellHWDetection


# Setup user profile disk shares
# ------------------------------
Write-Host -ForegroundColor Cyan "Creating user profile disk shares..."
ForEach (`$sharePath in ("F:\AppFileShares", "G:\RDPFileShares")) {
    `$_ = New-Item -ItemType Directory -Force -Path `$sharePath
    if(`$(Get-SmbShare | Where-Object -Property Path -eq `$sharePath) -eq `$null) {
        New-SmbShare -Path `$sharePath -Name `$sharePath.Split("\")[1] -FullAccess "$sreNetbiosName\$rdsGatewayVmName$","$sreNetbiosName\$rdsSh1VmName$","$sreNetbiosName\Domain Admins"
    }
}


# Remove any old RDS settings
# ---------------------------
ForEach (`$collection in `$(Get-RDSessionCollection -ErrorAction SilentlyContinue)) {
    Write-Host -ForegroundColor Cyan "Removing existing RDSessionCollection: '`$collection.CollectionName' (and associated apps)"
    Remove-RDSessionCollection -CollectionName `$collection.CollectionName -Force -ErrorAction SilentlyContinue
}
ForEach (`$server in `$(Get-RDServer -ErrorAction SilentlyContinue)) {
    Write-Host -ForegroundColor Cyan "Removing existing RDServer: '`$(`$server.Server)'"
    ForEach (`$role in `$server.Roles) {
        Remove-RDServer -Server `$server.Server -Role `$role -Force -ErrorAction SilentlyContinue
    }
}


# Create RDS Environment
# ----------------------
Write-Host -ForegroundColor Cyan "Creating RDS Environment..."
New-RDSessionDeployment -ConnectionBroker "$rdsGatewayVmName.$sreFqdn" -WebAccessServer "$rdsGatewayVmName.$sreFqdn" -SessionHost @("$rdsSh1VmName.$sreFqdn","$rdsSh2VmName.$sreFqdn")
Add-RDServer -Server $rdsGatewayVmName.$sreFqdn -Role RDS-LICENSING -ConnectionBroker $rdsGatewayVmName.$sreFqdn
Set-RDLicenseConfiguration -LicenseServer $rdsGatewayVmName.$sreFqdn -Mode PerUser -ConnectionBroker $rdsGatewayVmName.$sreFqdn -Force
Add-WindowsFeature -Name RDS-Gateway -IncludeAllSubFeature
Add-RDServer -Server $rdsGatewayVmName.$sreFqdn -Role RDS-GATEWAY -ConnectionBroker $rdsGatewayVmName.$sreFqdn -GatewayExternalFqdn $rdsGatewayVmName.$sreFqdn


# Create collections
# ------------------
`$collectionName = "Remote Applications"
Write-Host -ForegroundColor Cyan "Creating '`$collectionName' collection..."
New-RDSessionCollection -CollectionName "`$collectionName" -SessionHost $rdsSh1VmName.$sreFqdn -ConnectionBroker $rdsGatewayVmName.$sreFqdn
Set-RDSessionCollectionConfiguration -CollectionName "`$collectionName" -UserGroup "$shmNetbiosName\SG $sreNetbiosName Research Users" -ClientPrinterRedirected `$false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker $rdsGatewayVmName.$sreFqdn
Set-RDSessionCollectionConfiguration -CollectionName "`$collectionName" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\$rdsGatewayVmName\AppFileShares -ConnectionBroker $rdsGatewayVmName.$sreFqdn

`$collectionName = "Presentation Server"
Write-Host -ForegroundColor Cyan "Creating '`$collectionName' collection..."
New-RDSessionCollection -CollectionName "`$collectionName" -SessionHost $rdsSh2VmName.$sreFqdn -ConnectionBroker $rdsGatewayVmName.$sreFqdn
Set-RDSessionCollectionConfiguration -CollectionName "`$collectionName" -UserGroup "$shmNetbiosName\SG $sreNetbiosName Research Users" -ClientPrinterRedirected `$false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker $rdsGatewayVmName.$sreFqdn
Set-RDSessionCollectionConfiguration -CollectionName "`$collectionName" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\$rdsGatewayVmName\RDPFileShares -ConnectionBroker $rdsGatewayVmName.$sreFqdn


# Create applications
# -------------------
Write-Host -ForegroundColor Cyan "Creating applications..."
New-RDRemoteApp -Alias WinSCP -DisplayName "File Transfer" -FilePath "C:\Program Files (x86)\WinSCP\WinSCP.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker $rdsGatewayVmName.$sreFqdn
New-RDRemoteApp -Alias "chrome (1)" -DisplayName "GitLab" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://$dataSubnetIpPrefix.151" -CollectionName "Remote Applications" -ConnectionBroker $rdsGatewayVmName.$sreFqdn
New-RDRemoteApp -Alias "chrome (2)" -DisplayName "HackMD" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://$dataSubnetIpPrefix.152:3000" -CollectionName "Remote Applications" -ConnectionBroker $rdsGatewayVmName.$sreFqdn
New-RDRemoteApp -Alias "mstc (1)" -DisplayName "Data Science VM (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-v $dataSubnetIpPrefix.160" -CollectionName "Remote Applications" -ConnectionBroker $rdsGatewayVmName.$sreFqdn
New-RDRemoteApp -Alias "mstc (2)" -DisplayName "Additional VMs (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker $rdsGatewayVmName.$sreFqdn
New-RDRemoteApp -Alias "putty (1)" -DisplayName "Data Science VM (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-ssh $dataSubnetIpPrefix.160" -CollectionName "Remote Applications" -ConnectionBroker $rdsGatewayVmName.$sreFqdn
New-RDRemoteApp -Alias "putty (2)" -DisplayName "Additional VMs (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker $rdsGatewayVmName.$sreFqdn


# Update server configuration
# ---------------------------
Write-Host -ForegroundColor Cyan "Updating server configuration..."
`$targetDirectoryLocal = "C:\Users\$dcAdminUsername\AppData\Roaming\Microsoft\Windows\ServerManager"
`$targetDirectoryDomain = "C:\Users\$dcAdminUsername.$sreNetbiosName\AppData\Roaming\Microsoft\Windows\ServerManager"
`$_ = New-Item -ItemType Directory -Force -Path `$targetDirectoryLocal
`$_ = New-Item -ItemType Directory -Force -Path `$targetDirectoryDomain
Get-Process ServerManager -ErrorAction SilentlyContinue | Stop-Process -Force
Copy-Item -Path "$remoteUploadDir\ServerList.xml" -Destination "`$targetDirectoryLocal\ServerList.xml" -Force
Copy-Item -Path "$remoteUploadDir\ServerList.xml" -Destination "`$targetDirectoryDomain\ServerList.xml" -Force
Start-Process -FilePath $env:SystemRoot\System32\ServerManager.exe -WindowStyle Maximized
if ($?) {
    Write-Host " [o] Server configuration update succeeded"
} else {
    Write-Host " [x] Server configuration update failed!"
}


# Install RDS webclient
# ---------------------
Write-Host "Installing RDS webclient..."
Install-RDWebClientPackage
if ($?) {
    Write-Host " [o] RDS webclient installation succeeded"
} else {
    Write-Host " [x] RDS webclient installation failed!"
}