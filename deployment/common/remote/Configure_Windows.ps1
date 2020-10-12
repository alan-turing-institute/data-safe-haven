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
    [string]$NTPServer = ""
)


# Set locale
# ----------
Write-Output "Setting locale..."
Set-WinHomeLocation -GeoId 0xf2
$success = $?
Set-WinSystemLocale en-GB
$success = $success -and $?
Set-Culture en-GB
$success = $success -and $?
Set-WinUserLanguageList -LanguageList en-GB -Force
$success = $success -and $?
Get-WinUserLanguageList
if ($success) {
    Write-Output " [o] Setting locale succeeded"
} else {
    Write-Output " [x] Setting locale failed!"
}


# Configure time zone
# -------------------
if ($TimeZone) {
    Write-Output "Setting timezone and NTP server..."
    Set-TimeZone -Name $TimeZone
    if ($?) {
        Write-Output " [o] Setting time zone succeeded"
    } else {
        Write-Output " [x] Setting time zone failed!"
    }
} else {
    Write-Output " [x] Invalid time zone '$TimeZone' provided!"
}


# Configure NTP server
# These steps follow the instructions from https://support.microsoft.com/en-gb/help/816042/how-to-configure-an-authoritative-time-server-in-windows-server
# --------------------------------------------------------------------------------------------------------------------------------------------------------
if ($NTPServer) {
    # Change DateTime\Servers settings
    # We should end up with exactly two DWORDs: 0th-server and default (pointing to 0th-server)
    # -----------------------------------------------------------------------------------------
    Push-Location
    $success = $success -and $?
    Set-Location HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DateTime\Servers
    $success = $success -and $?
    Remove-ItemProperty . -Name "*"
    $success = $success -and $?
    Set-ItemProperty . 0 $NTPServer
    $success = $success -and $?
    Set-ItemProperty . "(Default)" "0"
    $success = $success -and $?
    $success = $success -and (((Get-ItemProperty .).PSObject.Members | Where-Object { $_.MemberType -eq "NoteProperty" -and $_.Name -notlike "PS*" } | Measure-Object | Select-Object Count).Count -eq 2)
    Pop-Location
    $success = $success -and $?

    # Change Services\W32Time settings
    # --------------------------------
    Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters Type NTP
    $success = $success -and $?
    Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters NtpServer "$NTPServer,0x1"
    $success = $success -and $?
    Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Config AnnounceFlags 0xA
    $success = $success -and $?
    Set-ItemProperty HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\TimeProviders\NtpServer Enabled 1
    $success = $success -and $?

    # Restart the Windows Time service
    # --------------------------------
    Stop-Service W32Time
    $success = $success -and $?
    Start-Service W32Time
    $success = $success -and $?
    if ($success) {
        Write-Output " [o] Setting NTP server succeeded"
    } else {
        Write-Output " [x] Setting NTP server failed!"
    }
} else {
    Write-Output " [x] Invalid NTP server '$NTPServer' provided!"
}


# Install Windows updates
# Iterate five times to ensure that we catch dependencies
# -------------------------------------------------------
$existingUpdateTitles = Get-WUHistory | Where-Object { ($_.Result -eq "Succeeded") } | ForEach-Object { $_.Title }
for ($i = 0; $i -lt 5; $i++) {
    $updatesToInstall = Get-WindowsUpdate -MicrosoftUpdate
    if ($updatesToInstall.Count) {
        Write-Output "`nInstalling $($updatesToInstall.Count) Windows updates:"
        foreach ($update in $updatesToInstall) {
            Write-Output " ... $($update.Title)"
        }
        Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot 2>&1 | Out-Null
        if ($?) {
            Write-Output " [o] Installing Windows updates succeeded."
        } else {
            Write-Output " [x] Installing Windows updates failed!"
        }
    }
}


# Report any updates that were installed
# --------------------------------------
Write-Output "`nNewly installed Windows updates:"
$installedUpdates = Get-WUHistory | Where-Object { ($_.Result -eq "Succeeded") -And ($_.Title -NotIn $existingUpdateTitles) }
foreach ($update in $installedUpdates) {
    Write-Output " ... $($update.Title)"
}
