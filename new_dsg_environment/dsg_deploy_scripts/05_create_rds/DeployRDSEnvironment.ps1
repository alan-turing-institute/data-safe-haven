Param(
  [Parameter(Mandatory = $true, 
             HelpMessage="Enter Netbios name i.e. DSGROUP2")]
  [ValidateNotNullOrEmpty()]
  [string]$domain,

  [Parameter(Mandatory = $true, 
             HelpMessage="Enter DSG name i.e. DSG2")]
  [ValidateNotNullOrEmpty()]
  [string]$dsg,

  [Parameter(Mandatory = $true, 
             HelpMessage="Enter Netbios name of the management domain i.e. TURINGSAFEHAVEN")]
  [ValidateNotNullOrEmpty()]
  [string]$mgmtdomain,


  [Parameter(Mandatory = $true, 
             HelpMessage="Enter IP address space of Subnet-Data minus the host number i.e. 10.250.10")]
  [ValidateNotNullOrEmpty()]
  [string]$ipaddress
)

#Initialise  the data drives
Stop-Service ShellHWDetection

$CandidateRawDisks = Get-Disk |  Where {$_.PartitionStyle -eq 'raw'} | Sort -Property Number
Foreach ($RawDisk in $CandidateRawDisks) {
    $LUN = (Get-WmiObject Win32_DiskDrive | Where index -eq $RawDisk.Number | Select SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    $Disk = Initialize-Disk -PartitionStyle GPT -Number $RawDisk.Number
    $Partition = New-Partition -DiskNumber $RawDisk.Number -UseMaximumSize -AssignDriveLetter
    $Volume = Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel "DATA-$LUN" -Confirm:$false
}

Start-Service ShellHWDetection

#Create RDS Environment
Write-Host -ForegroundColor Green "Creating RDS Environment" 
New-RDSessionDeployment -ConnectionBroker "RDS.$domain.co.uk" -WebAccessServer "RDS.$domain.co.uk" -SessionHost @("RDSSH1.$domain.co.uk","RDSSH2.$domain.co.uk")
Write-Host -ForegroundColor Green "Creating licensing server" 
Add-RDServer -Server rds.$domain.co.uk -Role RDS-LICENSING -ConnectionBroker rds.$domain.co.uk
Set-RDLicenseConfiguration -LicenseServer rds.$domain.co.uk -Mode PerUser -ConnectionBroker rds.$domain.co.uk -Force
Write-Host -ForegroundColor Green "Creating gateway server" 
Add-WindowsFeature -Name RDS-Gateway -IncludeAllSubFeature
Add-RDServer -Server rds.$domain.co.uk -Role RDS-GATEWAY -ConnectionBroker rds.$domain.co.uk -GatewayExternalFqdn rds.$domain.co.uk

#Setup user profile disk shares
Write-Host -ForegroundColor Green "Creating user profile disk shares" 
Mkdir "F:\AppFileShares"
Mkdir "G:\RDPFileShares"
New-SmbShare -Path "F:\AppFileShares" -Name "AppFileShares" -FullAccess "$domain\rds$","$domain\rdssh1$","$domain\domain admins"
New-SmbShare -Path "G:\RDPFileShares" -Name "RDPFileShares" -FullAccess "$domain\rds$","$domain\rdssh2$","$domain\domain admins"

#Create collections
Write-Host -ForegroundColor Green "Creating Collections" 
New-RDSessionCollection -CollectionName "Remote Applications" -SessionHost rdssh1.$domain.co.uk -ConnectionBroker rds.$domain.co.uk
Set-RDSessionCollectionConfiguration -CollectionName "Remote Applications" -UserGroup "$mgmtdomain\SG $dsg Research Users" -ClientPrinterRedirected $false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker rds.$domain.co.uk
Set-RDSessionCollectionConfiguration -CollectionName "Remote Applications" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\rds\AppFileShares  -ConnectionBroker rds.$domain.co.uk

New-RDSessionCollection -CollectionName "Presentation Server" -SessionHost rdssh2.$domain.co.uk -ConnectionBroker rds.$domain.co.uk 
Set-RDSessionCollectionConfiguration -CollectionName "Presentation Server" -UserGroup "$mgmtdomain\SG $dsg Research Users" -ClientPrinterRedirected $false -ClientDeviceRedirectionOptions None -DisconnectedSessionLimitMin 5 -IdleSessionLimitMin 720 -ConnectionBroker rds.$domain.co.uk
Set-RDSessionCollectionConfiguration -CollectionName "Presentation Server" -EnableUserProfileDisk -MaxUserProfileDiskSizeGB "20" -DiskPath \\rds\RDPFileShares  -ConnectionBroker rds.$domain.co.uk

Write-Host -ForegroundColor Green "Creating Apps"
New-RDRemoteApp -Alias mstc -DisplayName "Custom VM (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$domain.co.uk
New-RDRemoteApp -Alias putty -DisplayName "Custom VM (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$domain.co.uk
New-RDRemoteApp -Alias WinSCP -DisplayName "File Transfer" -FilePath "C:\Program Files (x86)\WinSCP\WinSCP.exe" -ShowInWebAccess 1 -CollectionName "Remote Applications" -ConnectionBroker rds.$domain.co.uk
New-RDRemoteApp -Alias "chrome (1)" -DisplayName "Git Lab" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://$ipaddress.151" -CollectionName "Remote Applications" -ConnectionBroker rds.$domain.co.uk 
New-RDRemoteApp -Alias 'chrome (2)' -DisplayName "HackMD" -FilePath "C:\Program Files (x86)\Google\Chrome\Application\chrome.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "http://$ipaddress.152:3000" -CollectionName "Remote Applications" -ConnectionBroker rds.$domain.co.uk 
New-RDRemoteApp -Alias "putty (1)" -DisplayName "Shared VM (SSH)" -FilePath "C:\Program Files\PuTTY\putty.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-ssh $ipaddress.160" -CollectionName "Remote Applications" -ConnectionBroker rds.$domain.co.uk
New-RDRemoteApp -Alias 'mstc (2)' -DisplayName "Shared VM (Desktop)" -FilePath "C:\Windows\system32\mstsc.exe" -ShowInWebAccess 1 -CommandLineSetting Require -RequiredCommandLine "-v $ipaddress.160" -CollectionName "Remote Applications" -ConnectionBroker rds.$domain.co.uk

Write-Host -ForegroundColor Green "All done!"