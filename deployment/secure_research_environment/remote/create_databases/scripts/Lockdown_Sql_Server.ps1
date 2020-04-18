# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $true, HelpMessage = "Whether SSIS should be disabled")]
    [string]$EnableSSIS,  # it is not possible to pass a bool through the Invoke-RemoteScript interface
    [Parameter(Mandatory = $true, HelpMessage = "Domain-qualified name for the SQL admin group")]
    [string]$SqlAdminGroup,
    [Parameter(Mandatory = $true, HelpMessage = "Name of SQL AuthUpdate User")]
    [string]$SqlAuthUpdateUsername,
    [Parameter(Mandatory = $true, HelpMessage = "Password for SQL AuthUpdate User")]
    [string]$SqlAuthUpdateUserPassword,
    [Parameter(Mandatory = $true, HelpMessage = "Server lockdown script")]
    [string]$B64ServerLockdownCommand
)

$serverName = $(hostname)
$secureSqlAuthUpdateUserPassword = (ConvertTo-SecureString $SqlAuthUpdateUserPassword -AsPlainText -Force)
$sqlAdminCredentials = New-Object System.Management.Automation.PSCredential($SqlAuthUpdateUsername, $secureSqlAuthUpdateUserPassword)
$connectionTimeoutInSeconds = 5
$EnableSSIS = [System.Convert]::ToBoolean($EnableSSIS)


# Ensure that SSIS is enabled/disabled as requested
# -------------------------------------------------
if ($EnableSSIS) {
    Write-Output "Ensuring that SSIS is enabled on: '$serverName'"
    Get-Service SSISTELEMETRY150, MsDtsServer150 | Start-Service -PassThru | Set-Service -StartupType Automatic
} else {
    Write-Output "Ensuring that SSIS is disabled on: '$serverName'"
    Get-Service SSISTELEMETRY150, MsDtsServer150 | Stop-Service -PassThru | Set-Service -StartupType Disabled
}
if ($?) {
    Write-Output " [o] Successfully set SSIS state on: '$serverName'"
} else {
    Write-Output " [x] Failed to set SSIS state on: '$serverName'!"
    exit 1
}


# Give the configured domain group the sysadmin role on the SQL Server
# --------------------------------------------------------------------
Write-Host "Ensuring that adminstrators domain group has SQL login access to: '$serverName'..."
if (Get-SqlLogin -ServerInstance $serverName -Credential $sqlAdminCredentials | Where-Object { $_.Name -eq $SqlAdminGroup } ) {
    Write-Host " [o] Adminstrators domain group already has SQL login access to: '$serverName'"
} else {
    Write-Host "Giving adminstrators domain group SQL login access to: '$serverName'..."
    $_ = Add-SqlLogin -ConnectionTimeout $connectionTimeoutInSeconds -GrantConnectSql -ServerInstance $serverName -LoginName $SqlAdminGroup -LoginType "WindowsGroup" -Credential $sqlAdminCredentials -ErrorAction Stop
    if ($?) {
        Write-Output " [o] Successfully gave domain group '$SqlAdminGroup' SQL login access to: '$serverName'"
    } else {
        Write-Output " [x] Failed to give domain group '$SqlAdminGroup' SQL login access to: '$serverName'!"
        exit 1
    }
}


# Run the scripted SQL Server lockdown
# ------------------------------------
Write-Host "Running T-SQL lockdown script on: '$serverName'..."
$ServerLockdownCommand = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($B64ServerLockdownCommand))
Invoke-SqlCmd -ServerInstance $serverName -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $ServerLockdownCommand -ErrorAction Stop
if ($?) {
    Write-Output " [o] Successfully ran T-SQL lockdown script on: '$serverName'"
} else {
    Write-Output " [x] Failed to run T-SQL lockdown script on: '$serverName'!"
    exit 1
}


# Disable unused SQL Server services
# ----------------------------------
Write-Host "Disable unused SQL server services on: '$serverName'..."
Get-Service SSASTELEMETRY, MSSQLServerOlapService, SQLBrowser | Stop-Service -PassThru | Set-Service -StartupType disabled
if ($?) {
    Write-Output " [o] Successfully disabled unused SQL server services on: '$serverName'"
} else {
    Write-Output " [x] Failed to disable unused SQL server services on: '$serverName'!"
    exit 1
}


# Revoke the sysadmin role from the SQL AuthUpdateUser used when building the SQL Server
# --------------------------------------------------------------------------------------
Write-Host "Revoking sysadmin role from $SqlAuthUpdateUsername on: '$serverName'..."
$dropAdminCommand = "ALTER SERVER ROLE sysadmin DROP MEMBER $($sqlLoginName)"
Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $dropAdminCommand -ErrorAction Stop
if ($?) {
    Write-Output " [o] Successfully revoked sysadmin role on: '$serverName'"
} else {
    Write-Output " [x] Failed to revoke sysadmin role on: '$serverName'!"
    exit 1
}
