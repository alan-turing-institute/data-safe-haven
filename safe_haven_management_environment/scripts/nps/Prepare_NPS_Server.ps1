Write-Host -Foregroundcolor Green "Settng locale and timezone...."
Set-WinHomeLocation -GeoId 0xf2
Set-TimeZone -Name "GMT Standard Time"
Set-WinSystemLocale en-GB
Set-Culture en-GB
Set-WinUserLanguageList -LanguageList (New-WinUserLanguageList -Language en-GB) -Force
write-Host -ForegroundColor Cyan "Completed"

Write-Host -Foregroundcolor Green "Installing NPS feature..."
Install-WindowsFeature NPAS -IncludeManagementTools
write-Host -ForegroundColor Cyan "Completed"

Write-Host -Foregroundcolor Green "Settng SQL Firewall rules"
New-NetFirewallRule -DisplayName "SQL" -Direction Inbound -Action Allow -Protocol TCP -LocalPort 1433 -Profile Domain -Enabled True
New-NetFirewallRule -DisplayName "SQL" -Direction Outbound -Action Allow -Protocol TCP -LocalPort 1433 -Profile Domain -Enabled True
write-Host -ForegroundColor Cyan "Completed"

Write-Host -Foregroundcolor Green "Settng Inbound RADIUS traffic from DSG environments rule"
New-NetFirewallRule -DisplayName "Inbound RADIUS traffic from DSG environments" -Direction Inbound -RemoteAddress 10.250.1.250 -Action Allow -Protocol UDP -LocalPort "1812","1813" -Profile Domain -Enabled True
write-Host -ForegroundColor Cyan "Completed"

#Initialise  the data drives
Write-Host -Foregroundcolor Green "Formatting data drive"
Stop-Service ShellHWDetection

$CandidateRawDisks = Get-Disk |  Where {$_.PartitionStyle -eq 'raw'} | Sort -Property Number
Foreach ($RawDisk in $CandidateRawDisks) {
    $LUN = (Get-WmiObject Win32_DiskDrive | Where index -eq $RawDisk.Number | Select SCSILogicalUnit -ExpandProperty SCSILogicalUnit)
    $Disk = Initialize-Disk -PartitionStyle GPT -Number $RawDisk.Number
    $Partition = New-Partition -DiskNumber $RawDisk.Number -UseMaximumSize -AssignDriveLetter
    $Volume = Format-Volume -Partition $Partition -FileSystem NTFS -NewFileSystemLabel "SQLDATA" -Confirm:$false
}
Start-Service ShellHWDetection
write-Host -ForegroundColor Cyan "Completed"