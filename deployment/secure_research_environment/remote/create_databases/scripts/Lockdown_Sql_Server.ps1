# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $true, HelpMessage = "Domain-qualified name for the SRE-level data administrators group")]
    [string]$DataAdminGroup,
    [Parameter(Mandatory = $true, HelpMessage = "Password for SQL AuthUpdate User")]
    [string]$DbAdminPassword,
    [Parameter(Mandatory = $true, HelpMessage = "Name of SQL AuthUpdate User")]
    [string]$DbAdminUsername,
    [Parameter(Mandatory = $true, HelpMessage = "Whether SSIS should be enabled")]
    [string]$EnableSSIS,  # it is not possible to pass a bool through the Invoke-RemoteScript interface
    [Parameter(Mandatory = $true, HelpMessage = "Domain-qualified name for the SRE-level research users group")]
    [string]$ResearchUsersGroup,
    [Parameter(Mandatory = $true, HelpMessage = "Server lockdown command")]
    [string]$ServerLockdownCommandB64,
    [Parameter(Mandatory = $true, HelpMessage = "Domain-qualified name for the SRE-level system administrators group")]
    [string]$SysAdminGroup,
    [Parameter(Mandatory = $true, HelpMessage = "Name of local admin user on this machine")]
    [string]$VmAdminUsername
)

Import-Module SqlServer

$serverName = $(hostname)
$secureDbAdminPassword = (ConvertTo-SecureString $DbAdminPassword -AsPlainText -Force)
$sqlAdminCredentials = New-Object System.Management.Automation.PSCredential($DbAdminUsername, $secureDbAdminPassword)
$connectionTimeoutInSeconds = 5
$EnableSSIS = [System.Convert]::ToBoolean($EnableSSIS)


# Ensure that SSIS is enabled/disabled as requested
# -------------------------------------------------
if ($EnableSSIS) {
    Write-Output "Ensuring that SSIS services (SSISTELEMETRY150, MsDtsServer150) are enabled on: '$serverName'"
    Get-Service SSISTELEMETRY150, MsDtsServer150 | Start-Service -PassThru | Set-Service -StartupType Automatic
} else {
    Write-Output "Ensuring that SSIS services (SSISTELEMETRY150, MsDtsServer150) are disabled on: '$serverName'"
    Get-Service SSISTELEMETRY150, MsDtsServer150 | Stop-Service -PassThru | Set-Service -StartupType Disabled
}
if ($?) {
    Write-Output " [o] Successfully updated SSIS services state on: '$serverName'"
} else {
    Write-Output " [x] Failed to updated SSIS services state on: '$serverName'!"
    exit 1
}


# Disable unused SQL Server services
# ----------------------------------
Write-Output "Disable unused SQL server services on: '$serverName'..."
Get-Service SSASTELEMETRY, MSSQLServerOlapService, SQLBrowser | Stop-Service -PassThru | Set-Service -StartupType disabled
if ($?) {
    Write-Output " [o] Successfully disabled unused services (SSASTELEMETRY, MSSQLServerOlapService, SQLBrowser) on: '$serverName'"
} else {
    Write-Output " [x] Failed to disable unused SQL server services on: '$serverName'!"
    exit 1
}


# Check whether the auth update user exists and has admin rights
# --------------------------------------------------------------
Write-Output "Checking that the $DbAdminUsername user has admin permissions on: '$serverName'..."
$loginExists = Get-SqlLogin -ServerInstance $serverName -Credential $sqlAdminCredentials -ErrorAction SilentlyContinue -ErrorVariable operationFailed | Where-Object { $_.Name -eq $DbAdminUsername }
$smo = (New-Object Microsoft.SqlServer.Management.Smo.Server $serverName)
$smo.ConnectionContext.LoginSecure = $false  # disable the default use of Windows credentials
$smo.ConnectionContext.set_Login($sqlAdminCredentials.UserName)
$smo.ConnectionContext.set_SecurePassword($sqlAdminCredentials.Password)
$isAdmin = $smo.Roles | Where-Object { $_.Name -Like "*admin*" } | Where-Object { $_.EnumServerRoleMembers() -Contains $DbAdminUsername }

# If the DbAdminUsername is not found then something has gone wrong
if ($operationFailed -Or (-Not $loginExists)) {
    Write-Output " [x] $DbAdminUsername does not exist on: '$serverName'!"
    exit 1

# If the DbAdminUsername is not an admin, then we are not able to do anything else.
# Hopefully this is because lockdown has already been run.
} elseif (-Not $isAdmin) {
    Write-Output " [o] $DbAdminUsername is not an admin on: '$serverName'. Have you already locked this server down?"

# ... otherwise we continue with the server lockdown
} else {
    Write-Output " [o] $DbAdminUsername has admin privileges on: '$serverName'"

    # Give the configured domain groups login access to the SQL Server
    # ----------------------------------------------------------------
    foreach ($domainGroup in @($SysAdminGroup, $DataAdminGroup, $ResearchUsersGroup)) {
        Write-Output "Ensuring that '$domainGroup' has SQL login access to: '$serverName'..."
        if (Get-SqlLogin -ServerInstance $serverName -Credential $sqlAdminCredentials | Where-Object { $_.Name -eq $domainGroup } ) {
            Write-Output " [o] '$domainGroup' already has SQL login access to: '$serverName'"
        } else {
            $null = Add-SqlLogin -ConnectionTimeout $connectionTimeoutInSeconds -GrantConnectSql -ServerInstance $serverName -LoginName $domainGroup -LoginType "WindowsGroup" -Credential $sqlAdminCredentials -ErrorAction SilentlyContinue -ErrorVariable operationFailed
            if ($? -And -Not $operationFailed) {
                Write-Output " [o] Successfully gave '$domainGroup' SQL login access to: '$serverName'"
            } else {
                Write-Output " [x] Failed to give '$domainGroup' SQL login access to: '$serverName'!"
                exit 1
            }
        }
        # Create a DB user for each login group
        Write-Output "Ensuring that an SQL user exists for '$domainGroup' on: '$serverName'..."
        $sqlCommand = "IF NOT EXISTS(SELECT * FROM sys.database_principals WHERE name = '$domainGroup') CREATE USER [$domainGroup] FOR LOGIN [$domainGroup];"
        Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $sqlCommand -ErrorAction SilentlyContinue -ErrorVariable sqlErrorMessage -OutputSqlErrors $true
        if ($? -And -Not $sqlErrorMessage) {
            Write-Output " [o] Ensured that '$domainGroup' user exists on: '$serverName'"
            Start-Sleep -s 10  # allow time for the database action to complete
        } else {
            Write-Output " [x] Failed to ensure that '$domainGroup' user exists on: '$serverName'!"
            Write-Output "Failed SQL command was: $sqlCommand"
            Write-Output "Error message: $sqlErrorMessage"
            exit 1
        }
    }

    # Create the data and public schemas
    # ----------------------------------
    foreach($groupSchemaTuple in @(($DataAdminGroup, "data"), ($ResearchUsersGroup, "dbopublic"))) {
        $domainGroup, $schemaName = $groupSchemaTuple
        $sqlCommand = "IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = N'$schemaName') EXEC('CREATE SCHEMA $schemaName AUTHORIZATION [$domainGroup]');"
        Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $sqlCommand -ErrorAction SilentlyContinue -ErrorVariable sqlErrorMessage -OutputSqlErrors $true
        if ($? -And -Not $sqlErrorMessage) {
            Write-Output " [o] Successfully ensured that '$schemaName' schema exists on: '$serverName'"
            Start-Sleep -s 10  # allow time for the database action to complete
        } else {
            Write-Output " [x] Failed to ensure that '$schemaName' schema exists on: '$serverName'!"
            Write-Output "Failed SQL command was: $sqlCommand"
            Write-Output "Error message: $sqlErrorMessage"
            exit 1
        }
    }


    # Give domain groups appropriate roles on the SQL Server
    # ------------------------------------------------------
    foreach($groupRoleTuple in @(($SysAdminGroup, "sysadmin"), ($DataAdminGroup, "dataadmin"), ($ResearchUsersGroup, "datareader"))) {
        $domainGroup, $role = $groupRoleTuple
        if ($role -eq "sysadmin") { # this is a server-level role
            $sqlCommand = "ALTER SERVER ROLE [$role] ADD MEMBER [$domainGroup];"
        } elseif ($role -eq "dataadmin") { # this is a schema-level role
            $sqlCommand = "GRANT CONTROL ON SCHEMA::data TO [$domainGroup];"
        } elseif ($role -eq "datareader") { # this is a schema-level role
            $sqlCommand = "GRANT SELECT ON SCHEMA::data TO [$domainGroup]; ALTER USER [$domainGroup] WITH DEFAULT_SCHEMA=[dbopublic]; GRANT CREATE TABLE TO [$domainGroup];"
        } else {
            Write-Output " [x] Role $role not recognised!"
            continue
        }
        Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $sqlCommand -ErrorAction SilentlyContinue -ErrorVariable sqlErrorMessage -OutputSqlErrors $true
        if ($? -And -Not $sqlErrorMessage) {
            Write-Output " [o] Successfully gave '$domainGroup' the $role role on: '$serverName'"
            Start-Sleep -s 10  # allow time for the database action to complete
        } else {
            Write-Output " [x] Failed to give '$domainGroup' the $role role on: '$serverName'!"
            Write-Output "Failed SQL command was: $sqlCommand"
            Write-Output "Error message: $sqlErrorMessage"
            exit 1
        }
    }


    # Run the scripted SQL Server lockdown
    # ------------------------------------
    Write-Output "Running T-SQL lockdown script on: '$serverName'..."
    $sqlCommand = [Text.Encoding]::Utf8.GetString([Convert]::FromBase64String($ServerLockdownCommandB64))
    Invoke-SqlCmd -ServerInstance $serverName -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $sqlCommand -ErrorAction SilentlyContinue -ErrorVariable sqlErrorMessage -OutputSqlErrors $true
    if ($? -And -Not $sqlErrorMessage) {
        Write-Output " [o] Successfully ran T-SQL lockdown script on: '$serverName'"
    } else {
        Write-Output " [x] Failed to run T-SQL lockdown script on: '$serverName'!"
        Write-Output "Failed SQL command was: $sqlCommand"
        Write-Output "Error message: $sqlErrorMessage"
        exit 1
    }


    # Removing database access from the local Windows admin
    # -----------------------------------------------------
    $windowsAdmin = "${serverName}\${VmAdminUsername}"
    Write-Output "Removing database access from $windowsAdmin on: '$serverName'..."
    $sqlCommand = "DROP USER IF EXISTS [$windowsAdmin]; IF EXISTS(SELECT * FROM master.dbo.syslogins WHERE loginname = '$windowsAdmin') DROP LOGIN [$windowsAdmin]"
    Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $sqlCommand -ErrorAction SilentlyContinue -ErrorVariable sqlErrorMessage -OutputSqlErrors $true
    if ($? -And -Not $sqlErrorMessage) {
        Write-Output " [o] Successfully removed database access for $windowsAdmin on: '$serverName'"
        Start-Sleep -s 10  # allow time for the database action to complete
    } else {
        Write-Output " [x] Failed to remove database access for $windowsAdmin on: '$serverName'!"
        Write-Output "Failed SQL command was: $sqlCommand"
        Write-Output "Error message: $sqlErrorMessage"
        exit 1
    }


    # Revoke the sysadmin role from the SQL AuthUpdateUser used to build the SQL Server
    # ---------------------------------------------------------------------------------
    Write-Output "Revoking sysadmin role from $DbAdminUsername on: '$serverName'..."
    $sqlCommand = "ALTER SERVER ROLE sysadmin DROP MEMBER $DbAdminUsername;"
    Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $sqlCommand -ErrorAction SilentlyContinue -ErrorVariable sqlErrorMessage -OutputSqlErrors $true
    if ($? -And -Not $sqlErrorMessage) {
        Write-Output " [o] Successfully revoked sysadmin role on: '$serverName'"
        Start-Sleep -s 10  # allow time for the database action to complete
    } else {
        Write-Output " [x] Failed to revoke sysadmin role on: '$serverName'!"
        Write-Output "Failed SQL command was: $sqlCommand"
        Write-Output "Error message: $sqlErrorMessage"
        exit 1
    }
}
