# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  [Parameter(Position=0, HelpMessage = "DSG fully qualified domain name")]
  [string]$dsgFqdn,
  [Parameter(Position=1, HelpMessage = "DSG Netbios name")]
  [string]$dsgNetbiosName,
  [Parameter(Position=2, HelpMessage = "SHM Netbios name")]
  [string]$shmNetbiosName,
  [Parameter(Position=3, HelpMessage = "First three octets of Data Subnet IP address range")]
  [string]$dataSubnetIpPrefix
)

Set-Executionpolicy Unrestricted

#Initialise the data drives
Stop-Service ShellHWDetection

$CandidateRawDisks = Get-Disk |  Where {$_.PartitionStyle -eq 'raw'} | Sort -Property Number
Foreach ($RawDisk in $CandidateRawDisks) {
    $LUN = (Get-WmiObject Win32_DiskDrive | Where index -eq $RawDisk.Number | Select SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    $Disk = Initialize-Disk -PartitionStyle GPT -Number $RawDisk.Number
    $Partition = New-Partition -DiskNumber $RawDisk.Number -UseMaximumSize -AssignDriveLetter
    $Volume = Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel "DATA-$LUN" -Confirm:$false
}

Start-Service ShellHWDetection

# Create RDS Environment
Write-Output "Creating RDS Environment" 
New-RDSessionDeployment -ConnectionBroker "RDS.$dsgFqdn" -WebAccessServer "RDS.$dsgFqdn" -SessionHost @("RDSSH1.$dsgFqdn","RDSSH2.$dsgFqdn")
Add-RDServer -Server rds.$dsgFqdn -Role RDS-LICENSING -ConnectionBroker rds.$dsgFqdn
Set-RDLicenseConfiguration -LicenseServer rds.$dsgFqdn -Mode PerUser -ConnectionBroker rds.$dsgFqdn -Force
Add-WindowsFeature -Name RDS-Gateway -IncludeAllSubFeature
Add-RDServer -Server rds.$dsgFqdn -Role RDS-GATEWAY -ConnectionBroker rds.$dsgFqdn -GatewayExternalFqdn rds.$dsgFqdn

# Setup user profile disk shares
Write-Host -ForegroundColor Green "Creating user profile disk shares" 
Mkdir "F:\AppFileShares"
Mkdir "G:\RDPFileShares"
New-SmbShare -Path "F:\AppFileShares" -Name "AppFileShares" -FullAccess "$dsgNetbiosName\rds$","$dsgNetbiosName\rdssh1$","$dsgNetbiosName\domain admins"
New-SmbShare -Path "G:\RDPFileShares" -Name "RDPFileShares" -FullAccess "$dsgNetbiosName\rds$","$dsgNetbiosName\rdssh2$","$dsgNetbiosName\domain admins"

# Create collections
Write-Host -ForegroundColor Green "Creating Collections" 
New-RDSessionCollection -CollectionName "Remote Applications" -SessionHost rdssh1.$dsgFqdn -ConnectionBroker rds.$dsgFqdn
Set-RDSessionCollectionConfiguration -CollectionName "Remote Applications" -UserGroup "$shmNetbiosName\SG $dsgNetbiosName Research Users" -ClientPrinterRedirected $false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker rds.$dsgFqdn
Set-RDSessionCollectionConfiguration -CollectionName "Remote Applications" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\rds\AppFileShares  -ConnectionBroker rds.$dsgFqdn

New-RDSessionCollection -CollectionName "Presentation Server" -SessionHost rdssh2.$dsgFqdn -ConnectionBroker rds.$dsgFqdn 
Set-RDSessionCollectionConfiguration -CollectionName "Presentation Server" -UserGroup "$shmNetbiosName\SG $dsgNetbiosName Research Users" -ClientPrinterRedirected $false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker rds.$dsgFqdn
Set-RDSessionCollectionConfiguration -CollectionName "Presentation Server" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\rds\RDPFileShares  -ConnectionBroker rds.$dsgFqdn

Write-Host -ForegroundColor Green "Creating Apps"
New-RDRemoteApp -Alias mstc -DisplayName "Custom VM (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn
New-RDRemoteApp -Alias putty -DisplayName "Custom VM (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn
New-RDRemoteApp -Alias WinSCP -DisplayName "File Transfer" -FilePath "C:\Program Files (x86)\WinSCP\WinSCP.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn
New-RDRemoteApp -Alias "chrome (1)" -DisplayName "Git Lab" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://$dataSubnetIpPrefix.151" -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn 
New-RDRemoteApp -Alias 'chrome (2)' -DisplayName "HackMD" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://$dataSubnetIpPrefix.152:3000" -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn 
New-RDRemoteApp -Alias "putty (1)" -DisplayName "Shared VM (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-ssh $dataSubnetIpPrefix.160" -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn
New-RDRemoteApp -Alias 'mstc (2)' -DisplayName "Shared VM (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-v $dataSubnetIpPrefix.160" -CollectionName "Remote Applications" -ConnectionBroker rds.$dsgFqdn

# Install RDS webclient
Write-Output "Installing RDS webclient"
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name RDWebClientManagement -AcceptLicense
Install-RDWebClientPackage
Publish-RDWebClientPackage -Type Production -Latest