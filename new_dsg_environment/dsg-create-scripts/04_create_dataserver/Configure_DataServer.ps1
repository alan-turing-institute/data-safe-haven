Param(
  [Parameter(Mandatory = $true, 
             HelpMessage="Enter Netbios name of the Safe Haven Management Domain i.e. TURINGSAFEHAVEN")]
  [ValidateNotNullOrEmpty()]
  [string]$mgmtdomain,

  [Parameter(Mandatory = $true, 
             HelpMessage="Enter Netbios name of the DSG Domain i.e. DSGROUP2")]
  [ValidateNotNullOrEmpty()]
  [string]$dsgdomain,

  [Parameter(Mandatory = $true, 
             HelpMessage="Enter the DSG name i.e. DSG2")]
  [ValidateNotNullOrEmpty()]
  [string]$dsg

)

#Format data drive
Write-Host -ForegroundColor Green "Formatting data drive"
Stop-Service ShellHWDetection

$CandidateRawDisks = Get-Disk |  Where {$_.PartitionStyle -eq 'raw'} | Sort -Property Number
Foreach ($RawDisk in $CandidateRawDisks) {
    $LUN = (Get-WmiObject Win32_DiskDrive | Where index -eq $RawDisk.Number | Select SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    $Disk = Initialize-Disk -PartitionStyle GPT -Number $RawDisk.Number
    $Partition = New-Partition -DiskNumber $RawDisk.Number -UseMaximumSize -AssignDriveLetter
    $Volume = Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel "DATA-$LUN" -Confirm:$false
}

Start-Service ShellHWDetection

#Setup user profile disk shares
Write-Host -ForegroundColor Green "Creating data share" 
Mkdir "F:\Data"
New-SmbShare -Path "F:\Data" -Name "Data" -ChangeAccess "$mgmtdomain\SG $dsg Research Users" -FullAccess "$dsgdomain\SG $dsgdomain Server Administrators"

#Set language and time-zone
Set-WinHomeLocation -GeoId 0xf2
Set-TimeZone -Name "GMT Standard Time"
Set-WinSystemLocale en-GB
Set-Culture en-GB
Set-WinUserLanguageList -LanguageList (New-WinUserLanguageList -Language en-GB) -Force

write-Host -ForegroundColor Cyan "Completed"