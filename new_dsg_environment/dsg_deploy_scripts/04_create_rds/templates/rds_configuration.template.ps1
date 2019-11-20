#Initialise the data drives
Stop-Service ShellHWDetection

`$CandidateRawDisks = Get-Disk |  Where {`$_.PartitionStyle -eq 'raw'} | Sort -Property Number
Foreach (`$RawDisk in `$CandidateRawDisks) {
    `$LUN = (Get-WmiObject Win32_DiskDrive | Where index -eq `$RawDisk.Number | Select SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    `$Disk = Initialize-Disk -PartitionStyle GPT -Number `$RawDisk.Number
    `$Partition = New-Partition -DiskNumber `$RawDisk.Number -UseMaximumSize -AssignDriveLetter
    `$Volume = Format-Volume -Partition `$Partition -FileSystem NTFS -NewFileSystemLabel "DATA-`$LUN" -Confirm:`$false
}

Start-Service ShellHWDetection

# Create RDS Environment
Write-Output "Creating RDS Environment"
New-RDSessionDeployment -ConnectionBroker "RDS.$sreFqdn" -WebAccessServer "RDS.$sreFqdn" -SessionHost @("RDSSH1.$sreFqdn","RDSSH2.$sreFqdn")
Add-RDServer -Server rds.$sreFqdn -Role RDS-LICENSING -ConnectionBroker rds.$sreFqdn
Set-RDLicenseConfiguration -LicenseServer rds.$sreFqdn -Mode PerUser -ConnectionBroker rds.$sreFqdn -Force
Add-WindowsFeature -Name RDS-Gateway -IncludeAllSubFeature
Add-RDServer -Server rds.$sreFqdn -Role RDS-GATEWAY -ConnectionBroker rds.$sreFqdn -GatewayExternalFqdn rds.$sreFqdn

# Setup user profile disk shares
Write-Host -ForegroundColor Green "Creating user profile disk shares"
Mkdir "F:\AppFileShares"
Mkdir "G:\RDPFileShares"
New-SmbShare -Path "F:\AppFileShares" -Name "AppFileShares" -FullAccess "$sreNetbiosName\rds$","$sreNetbiosName\rdssh1$","$sreNetbiosName\domain admins"
New-SmbShare -Path "G:\RDPFileShares" -Name "RDPFileShares" -FullAccess "$sreNetbiosName\rds$","$sreNetbiosName\rdssh2$","$sreNetbiosName\domain admins"

# Create collections
Write-Host -ForegroundColor Green "Creating Collections"
New-RDSessionCollection -CollectionName "Remote Applications" -SessionHost rdssh1.$sreFqdn -ConnectionBroker rds.$sreFqdn
Set-RDSessionCollectionConfiguration -CollectionName "Remote Applications" -UserGroup "$shmNetbiosName\SG $sreNetbiosName Research Users" -ClientPrinterRedirected `$false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker rds.$sreFqdn
Set-RDSessionCollectionConfiguration -CollectionName "Remote Applications" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\rds\AppFileShares  -ConnectionBroker rds.$sreFqdn

New-RDSessionCollection -CollectionName "Presentation Server" -SessionHost rdssh2.$sreFqdn -ConnectionBroker rds.$sreFqdn
Set-RDSessionCollectionConfiguration -CollectionName "Presentation Server" -UserGroup "$shmNetbiosName\SG $sreNetbiosName Research Users" -ClientPrinterRedirected `$false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker rds.$sreFqdn
Set-RDSessionCollectionConfiguration -CollectionName "Presentation Server" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\rds\RDPFileShares  -ConnectionBroker rds.$sreFqdn

Write-Host -ForegroundColor Green "Creating Apps"
New-RDRemoteApp -Alias mstc -DisplayName "Custom VM (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$sreFqdn
New-RDRemoteApp -Alias putty -DisplayName "Custom VM (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$sreFqdn
New-RDRemoteApp -Alias WinSCP -DisplayName "File Transfer" -FilePath "C:\Program Files (x86)\WinSCP\WinSCP.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$sreFqdn
New-RDRemoteApp -Alias "chrome (1)" -DisplayName "Git Lab" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://$dataSubnetIpPrefix.151" -CollectionName "Remote Applications" -ConnectionBroker rds.$sreFqdn
New-RDRemoteApp -Alias 'chrome (2)' -DisplayName "HackMD" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://$dataSubnetIpPrefix.152:3000" -CollectionName "Remote Applications" -ConnectionBroker rds.$sreFqdn
New-RDRemoteApp -Alias "putty (1)" -DisplayName "Shared VM (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-ssh $dataSubnetIpPrefix.160" -CollectionName "Remote Applications" -ConnectionBroker rds.$sreFqdn
New-RDRemoteApp -Alias 'mstc (2)' -DisplayName "Shared VM (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-v $dataSubnetIpPrefix.160" -CollectionName "Remote Applications" -ConnectionBroker rds.$sreFqdn
