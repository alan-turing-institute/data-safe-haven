# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $false, HelpMessage = "Time zone to use")]
    [string]$TimeZone = "",
    [Parameter(Mandatory = $false, HelpMessage = "NTP server to use")]
    [string]$NTPServer = "",
    [Parameter(Mandatory = $false, HelpMessage = "Locale to use")]
    [string]$Locale = "en-GB"
)


# Set locale
# ----------
Write-Output "Setting locale..."
$GeoId = ([System.Globalization.CultureInfo]::GetCultures("InstalledWin32Cultures") | Where-Object { $_.Name -eq $Locale } | ForEach-Object { [System.Globalization.RegionInfo]$_.Name }).GeoId
Set-WinHomeLocation -GeoId $GeoId
Set-WinSystemLocale -SystemLocale $Locale
Set-Culture -CultureInfo $Locale
Set-WinUserLanguageList -LanguageList $Locale -Force
if (((Get-Culture).Name -eq $Locale) -and ((Get-WinUserLanguageList)[0].LanguageTag -eq $Locale)) {
    # Note that Set-WinSystemLocale will not be applied until after a restart
    Write-Output " [o] Setting locale to '$Locale' succeeded"
} else {
    Write-Output " [x] Setting locale to '$Locale' failed!"
}


# Configure time zone
# -------------------
if ($TimeZone) {
    Write-Output "Setting time zone..."
    Set-TimeZone -Name $TimeZone
    if ($?) {
        Write-Output " [o] Setting time zone to '$TimeZone' succeeded"
    } else {
        Write-Output (Get-TimeZone)
        Write-Output " [x] Setting time zone to '$TimeZone' failed!"
    }
} else {
    Write-Output " [x] Invalid time zone '$TimeZone' provided!"
}


# Configure NTP server
# These steps follow the instructions from https://support.microsoft.com/en-gb/help/816042/how-to-configure-an-authoritative-time-server-in-windows-server
# --------------------------------------------------------------------------------------------------------------------------------------------------------
if ($NTPServer) {
    Write-Output "Setting NTP server..."
    $success = $true
    # Change DateTime\Servers settings
    # We should end up with exactly two DWORDs: 0th-server and default (pointing to 0th-server)
    # -----------------------------------------------------------------------------------------
    Push-Location
    Set-Location HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers
    Remove-ItemProperty . -Name "*"
    Set-ItemProperty . 0 $NTPServer
    Set-ItemProperty . "(Default)" "0"
    Pop-Location
    $success = $success -and (
        (((Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers).PSObject.Members | Where-Object { $_.MemberType -eq "NoteProperty" -and $_.Name -notlike "PS*" } | Measure-Object | Select-Object Count).Count -eq 2) -and
        ((Get-ItemPropertyValue HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers -Name "0") -eq $NTPServer) -and
        ((Get-ItemPropertyValue HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers -Name "(Default)") -eq "0")
    )

    # Change Services\W32Time settings
    # --------------------------------
    Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters Type NTP
    Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters NtpServer "$NTPServer,0x1"
    Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config AnnounceFlags 0xA
    Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer Enabled 1
    $success = $success -and (
        ((Get-ItemPropertyValue HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters -Name "Type") -eq "NTP") -and
        ((Get-ItemPropertyValue HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters -Name "NtpServer") -eq "$NTPServer,0x1") -and
        ((Get-ItemPropertyValue HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config -Name "AnnounceFlags") -eq 0xA) -and
        ((Get-ItemPropertyValue HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer -Name "Enabled") -eq 1)
    )

    # Restart the Windows Time service
    # --------------------------------
    Stop-Service W32Time
    Start-Service W32Time

    # Check that settings were applied
    # --------------------------------
    if ($success) {
        Write-Output " [o] Setting NTP server to '$NTPServer' succeeded"
    } else {
        Write-Output " [x] Setting NTP server to '$NTPServer' failed!"
    }
} else {
    Write-Output " [x] Invalid NTP server '$NTPServer' provided!"
}


# Install Windows updates
# -----------------------
$LogFilePath = "C:\Windows\Logs\Powershell\WindowsUpdate.$((Get-Date -Format FileDateTime).Substring(0, 13)).log"
$null = New-Item (Split-Path -Path $LogFilePath) -ItemType Directory -Force
$null = Add-WUServiceManager -ServiceID "7971f918-a847-4430-9279-4a52d1efe18d" -Confirm:$false # Register Microsoft Update servers
$updatesToInstall = Get-WindowsUpdate -MicrosoftUpdate
if ($updatesToInstall.Count) {
    Write-Output "`nFound $($updatesToInstall.Count) Windows updates to install:" | Tee-Object -FilePath $LogFilePath -Append
    $updatesToInstall | ForEach-Object { Write-Output " ... $($_.Title)" | Tee-Object -FilePath $LogFilePath -Append }
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot 2>&1 | Out-File $LogFilePath -Append
    if ($?) {
        Write-Output " [o] Installing Windows updates succeeded." | Tee-Object -FilePath $LogFilePath -Append
    } else {
        Write-Output " [x] Installing Windows updates failed!" | Tee-Object -FilePath $LogFilePath -Append
    }
}
