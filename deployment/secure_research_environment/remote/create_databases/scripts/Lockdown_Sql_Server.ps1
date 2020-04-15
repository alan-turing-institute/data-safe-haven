Import-Module Az
Import-Module SqlServer
Import-Module $PSScriptRoot/../../../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../../common/Security.psm1 -Force

Function Add-DevSqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
        [string]$SreId,       
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
        [string]$SqlServerName,       
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter the IP address for the VM")]
        [string]$SqlServerIpAddress       
    )

    $config = Get-SreConfig $sreId

    $params = @{
        sreId = $SreId
        subnetName = $config.sre.network.subnets.mssqldev.name
        subnetAddressPrefix = $config.sre.network.subnets.mssqldev.cidr
        resourceGroupName = $config.sre.mssqldev.rg
        sqlServerName = $SqlServerName
        sqlServerEdition = "sqldev"
        sqlServerVmSize = "Standard_GS1"
        sqlServerIpAddress = $SqlServerIpAddress
    }

    $_ = Add-SqlServer @params
}

Export-ModuleMember -Function Add-DevSqlServer

Function Add-EtlSqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
        [string]$SreId,       
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
        [string]$SqlServerName,       
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter the IP address for the VM")]
        [string]$SqlServerIpAddress       
    )

    $config = Get-SreConfig $sreId

    $params = @{
        sreId = $SreId
        subnetName = $config.sre.network.subnets.mssqletl.name
        subnetAddressPrefix = $config.sre.network.subnets.mssqletl.cidr
        resourceGroupName = $config.sre.mssqletl.rg
        sqlServerName = $SqlServerName
        sqlServerEdition = "enterprise"
        sqlServerVmSize = "Standard_GS1"
        sqlServerIpAddress = $SqlServerIpAddress
    }

    $_ = Add-SqlServer @params
}

Export-ModuleMember -Function Add-EtlSqlServer

Function Add-DataSqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
        [string]$SreId,       
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
        [string]$SqlServerName,       
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter the IP address for the VM")]
        [string]$SqlServerIpAddress       
    )

    $config = Get-SreConfig $sreId

    $params = @{
        sreId = $SreId
        subnetName = $config.sre.network.subnets.mssqldata.name
        subnetAddressPrefix = $config.sre.network.subnets.mssqldata.cidr
        resourceGroupName = $config.sre.mssqldata.rg
        sqlServerName = $SqlServerName
        sqlServerEdition = "enterprise"
        sqlServerVmSize = "Standard_GS2"
        sqlServerIpAddress = $SqlServerIpAddress
    }

    $_ = Add-SqlServer @params
}

Export-ModuleMember -Function Add-DataSqlServer

Function Add-SqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
        [string]$sreId,
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter name of the SRE subnet that will contain the SQL Server")]
        [string]$subnetName,
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter name of the SRE subnet that will contain the SQL Server")]
        [string]$subnetAddressPrefix,
        [Parameter(Position=3, Mandatory = $true, HelpMessage = "Enter name of the resource group that will contain the SQL Server")]
        [string]$resourceGroupName,
        [Parameter(Position=4, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
        [string]$sqlServerName,
        [Parameter(Position=5, Mandatory = $true, HelpMessage = "Enter the SQL Server Edition e.g. sqldev or enterprise")]
        [string]$sqlServerEdition,
        [Parameter(Position=6, Mandatory = $true, HelpMessage = "Enter the size of the VM e.g. Standard_GS1 or Standard_GS2")]
        [string]$sqlServerVmSize,
        [Parameter(Position=7, Mandatory = $true, HelpMessage = "Enter the IP address for the VM")]
        [string]$sqlServerIpAddress
    )

    $maximumSqlServerNameLength = 15
    If ($sqlServerName.length -gt $maximumSqlServerNameLength) {
        Add-LogMessage -Level Error "Sql Server Name: $($sqlServerName) is too long.  It needs to be $($maximumSqlServerNameLength) characters or less."
        Return        
    }

    # Get config and original context before changing subscription
    # ------------------------------------------------------------
    $config = Get-SreConfig $sreId
    $originalContext = Get-AzContext
    $_ = Set-AzContext -Subscription $config.sre.subscriptionName

    # Retrieve passwords from the keyvault
    # ------------------------------------
    Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
    $shmDcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminPassword
    $shmDcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.shm.id)admin".ToLower()
    $sreAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dataServerAdminPassword
    $sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
    $sqlAuthUpdateUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUserPassword
    $sqlAuthUpdateUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUsername -DefaultValue "sre$($config.sre.id)sqlauthupd".ToLower()

    # Create resource group if it does not exist
    # ------------------------------------------------------
    $_ = Deploy-ResourceGroup -Name $resourceGroupName -Location $config.sre.location

    # Create subnet if it does not exist
    # ------------------------------------------------------
    $virtualNetwork = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
    $subnet = Deploy-Subnet -Name $subnetName -VirtualNetwork $virtualNetwork -AddressPrefix $subnetAddressPrefix

    Add-LogMessage -Level Info "SQL Server: '$($sqlServerName)' will join subnet: '$($subnet.Id)'..."
   
    # Deploy SQL Server from template
    # --------------------------------
    Add-LogMessage -Level Info "Creating SQL Server: '$($sqlServerName)'' from template..."
    $params = @{
        Location = $config.sre.location;
        Administrator_Password = $sreAdminPassword;
        Administrator_User = $sreAdminUsername;
        DC_Join_Password = $shmDcAdminPassword;
        DC_Join_User = $shmDcAdminUsername;
        Sql_AuthUpdate_UserName = $sqlAuthUpdateUsername;
        Sql_AuthUpdate_Password = $sqlAuthUpdateUserPassword;
        BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName;
        Sql_Server_Name = $sqlServerName;
        Sql_Server_Edition = $sqlServerEdition;      
        Domain_Name = $config.shm.domain.fqdn;
        IP_Address = $sqlServerIpAddress;
        SubnetResourceId = $subnet.Id;  
        VM_Size = $sqlServerVmSize
    }

    $templateFile = (Join-Path $PSScriptRoot ".." ".." ".." "arm_templates" "customisations" "mssql" "sre-mssql2019-server-template.json")
    New-AzResourceGroupDeployment -TemplateFile $templateFile -TemplateParameterObject $params -ResourceGroupName $resourceGroupName -Verbose -DeploymentDebugLogLevel "All"

    # Switch back to original subscription
    # ------------------------------------
    $_ = Set-AzContext -Context $originalContext;
}

Export-ModuleMember -Function Add-SqlServer

Function Initialize-SqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
        [string]$SreId,
        [Parameter(Position=3, Mandatory = $true, HelpMessage = "Enter name of the resource group that will contain the SQL Server")]
        [string]$ResourceGroupName,
        [Parameter(Position=4, Mandatory = $true, HelpMessage = "Enter the name for the SQL Server VM")]
        [string]$SqlServerName,
        [Parameter(Position=7, Mandatory = $true, HelpMessage = "Enter the IP address for the VM")]
        [string]$SqlServerIpAddress,
        [Parameter(Position=8, Mandatory = $true, HelpMessage = "Enter whether SSIS should be disabled")]
        [bool]$DisableSSIS
    )

    # Get config and original context before changing subscription
    # ------------------------------------------------------------
    $config = Get-SreConfig $sreId
    $originalContext = Get-AzContext
    $_ = Set-AzContext -Subscription $config.sre.subscriptionName

    # Retrieve passwords from the keyvault
    # ------------------------------------
    Add-LogMessage -Level Info "Retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
    $sqlAuthUpdateUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUserPassword
    $sqlAuthUpdateUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUsername -DefaultValue "sre$($config.sre.id)sqlauthupd".ToLower()

    # Disable SSIS on the SQL Server, if parameter flag is set
    # --------------------------------
    if ($DisableSSIS) {
        Disable-SSIS -resourceGroupName $ResourceGroupName -sqlServerName $SqlServerName
    }

    # Give the configured domain group the sysadmin role on the SQL Server
    # --------------------------------
    $params = @{
        sreId = $SreId
        sqlServerIpAddress = $SqlServerIpAddress
        sqlAuthUpdateUsername = $SqlAuthUpdateUsername
        sqlAuthUpdateUserPassword = $SqlAuthUpdateUserPassword
    }
    $_ = Add-SqlAdminsDomainGroupToSqlServer @params

    # Run the scripted SQL Server lockdown
    # --------------------------------
    $params = @{
        sqlServerIpAddress = $SqlServerIpAddress
        sqlAuthUpdateUsername = $SqlAuthUpdateUsername
        sqlAuthUpdateUserPassword = $SqlAuthUpdateUserPassword
        resourceGroupName = $ResourceGroupName
        sqlServerName = $SqlServerName
    }
    $_ = Protect-SqlServer @params

    # Revoke the sysadmin role from the SQL AuthUpdateUser used when building the SQL Server
    # --------------------------------
    $params = @{
        sqlServerIpAddress = $SqlServerIpAddress
        sqlAuthUpdateUsername = $SqlAuthUpdateUsername
        sqlAuthUpdateUserPassword = $SqlAuthUpdateUserPassword
        sqlLoginName = $SqlAuthUpdateUsername
    }
    $_ = Revoke-SqlServerSysAdminRoleFromSqlLogin @params

    # Switch back to original subscription
    # ------------------------------------
    $_ = Set-AzContext -Context $originalContext;
}

Export-ModuleMember -Function Initialize-SqlServer

Function Revoke-SqlServerSysAdminRoleFromSqlLogin {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter the IP address for the SQL Server")]
        [string]$sqlServerIpAddress,
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter the SQL Auth Update Username for the SQL Server")]
        [string]$sqlAuthUpdateUsername,
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter the SQL Auth Update Password for the SQL Server")]
        [string]$sqlAuthUpdateUserPassword,
        [Parameter(Position=3, Mandatory = $true, HelpMessage = "Enter the name of the SQL Login to revoke the sysadmin role from")]
        [string]$sqlLoginName
    )

    # Build up parameters
    # ------------------------------------------------------------
    $sqlAdminCredentials = Get-SqlAdminCredentials -sqlAuthUpdateUsername $sqlAuthUpdateUsername -sqlAuthUpdateUserPassword $sqlAuthUpdateUserPassword
    $connectionTimeoutInSeconds = Get-SqlConnectionTimeout
    $serverInstance = Get-SqlServerInstanceAddress -sqlServerIpAddress $sqlServerIpAddress

    Add-LogMessage -Level Info "The sysadmin role will be revoked for '$($sqlLoginName)' on: '$($serverInstance)'..."  
    $tSqlCommand = "ALTER SERVER ROLE sysadmin DROP MEMBER $($sqlLoginName)"
    Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $tSqlCommand
    Add-LogMessage -Level Info "The sysadmin role has been revoked for '$($sqlLoginName)' on: '$($serverInstance)'..."
}

Export-ModuleMember -Function Revoke-SqlServerSysAdminRoleFromSqlLogin

Function Add-SqlAdminsDomainGroupToSqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
        [string]$sreId,
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter the IP address for the SQL Server")]
        [string]$sqlServerIpAddress,
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter the SQL Auth Update Username for the SQL Server")]
        [string]$sqlAuthUpdateUsername,
        [Parameter(Position=3, Mandatory = $true, HelpMessage = "Enter the SQL Auth Update Password for the SQL Server")]
        [string]$sqlAuthUpdateUserPassword
    )

    # Get config
    # ------------------------------------------------------------
    $config = Get-SreConfig $sreId
  
    # Build up parameters
    # ------------------------------------------------------------
    $sqlAdminCredentials = Get-SqlAdminCredentials -sqlAuthUpdateUsername $sqlAuthUpdateUsername -sqlAuthUpdateUserPassword $sqlAuthUpdateUserPassword
    $sqlLoginName = $config.shm.domain.netbiosName + "\" + $config.shm.domain.securityGroups.sqlAdmins.name
    $connectionTimeoutInSeconds = Get-SqlConnectionTimeout
    $serverInstance = Get-SqlServerInstanceAddress -sqlServerIpAddress $sqlServerIpAddress

    Add-LogMessage -Level Info "Domain Group: '$($sqlLoginName)' will be added as a SQL Login on: '$($serverInstance)'..."
    
    Try {
        $sqlLogin = Add-SqlLogin -ConnectionTimeout $connectionTimeoutInSeconds -GrantConnectSql -ServerInstance $serverInstance -LoginName $sqlLoginName -LoginType "WindowsGroup" -Credential $sqlAdminCredentials
    }
    Catch {
        Add-LogMessage -Level Error "Domain Group: '$($sqlLoginName)' NOT added as a SQL Login on: '$($serverInstance)' (does it already exist?)..."
        Return
    }
    
    Add-LogMessage -Level Info "Domain Group: '$($sqlLoginName)' added as a SQL Login on: '$($serverInstance)'..."

    Add-LogMessage -Level Info "'$($sqlLogin.Name)' will be given sysadmin role on: '$($serverInstance)'..."  
    $tSqlCommand = "exec sp_addsrvrolemember '$($sqlLogin.Name)', 'sysadmin'"
    Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -Query $tSqlCommand -ErrorAction Stop
    Add-LogMessage -Level Info "'$($sqlLogin.Name)' now has sysadmin role on: '$($serverInstance)'..."
}

Export-ModuleMember -Function Add-SqlAdminsDomainGroupToSqlServer

Function Protect-SqlServer {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter the IP address for the SQL Server")]
        [string]$sqlServerIpAddress,
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter the SQL Auth Update Username for the SQL Server")]
        [string]$sqlAuthUpdateUsername,
        [Parameter(Position=2, Mandatory = $true, HelpMessage = "Enter the SQL Auth Update Password for the SQL Server")]
        [string]$sqlAuthUpdateUserPassword,
        [Parameter(Position=3, Mandatory = $true, HelpMessage = "Enter name of the resource group that will contain the SQL Server")]
        [string]$resourceGroupName,
        [Parameter(Position=4, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
        [string]$sqlServerName
    )

    # Build up parameters
    # ------------------------------------------------------------
    $sqlAdminCredentials = Get-SqlAdminCredentials -sqlAuthUpdateUsername $sqlAuthUpdateUsername -sqlAuthUpdateUserPassword $sqlAuthUpdateUserPassword
    $connectionTimeoutInSeconds = Get-SqlConnectionTimeout
    $serverInstance = Get-SqlServerInstanceAddress -sqlServerIpAddress $sqlServerIpAddress

    $scriptFile = (Join-Path $PSScriptRoot ".." ".." ".." "tsql_scripts" "customisations" "mssql" "sre-mssql2019-server-lockdown.sql")

    Add-LogMessage -Level Info "T-SQL lockdown script will be run on: '$($serverInstance)'..."  
    Invoke-SqlCmd -ServerInstance $serverInstance -Credential $sqlAdminCredentials -QueryTimeout $connectionTimeoutInSeconds -InputFile $scriptFile -ErrorAction Stop
    Add-LogMessage -Level Info "T-SQL lockdown script completed on: '$($serverInstance)'..."

    Add-LogMessage -Level Info "Unused SQL Server services will be disabled on: '$($sqlServerName) [$($sqlServerIpAddress)]'..."
    
    # Run remote script
    $scriptPath = Join-Path $PSScriptRoot ".." ".." ".." "remote" "customisations" "mssql" "Disable_UnUsed_Sql_Server_Services.ps1" -Resolve
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $sqlServerName -ResourceGroupName $resourceGroupName
    Write-Output $result.Value
    
    Add-LogMessage -Level Info "Unused SQL Server services disabled on: '$($sqlServerName) [$($sqlServerIpAddress)]'..."
}

Export-ModuleMember -Function Protect-SqlServer

Function Disable-SSIS {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter name of the resource group that will contain the SQL Server")]
        [string]$resourceGroupName,
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter a name for the SQL Server VM")]
        [string]$sqlServerName
    )

    Add-LogMessage -Level Info "SSIS will be disabled on: '$($sqlServerName)'..."
    
    # Run remote script
    $scriptPath = Join-Path $PSScriptRoot ".." ".." ".." "remote" "customisations" "mssql" "Disable_SSIS_Sql_Server_Services.ps1" -Resolve
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $sqlServerName -ResourceGroupName $resourceGroupName
    Write-Output $result.Value
    
    Add-LogMessage -Level Info "SSIS disabled on: '$($sqlServerName)'..."
}

Export-ModuleMember -Function Disable-SSIS

Function Get-SqlAdminCredentials {
    param(
        [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter the SQL Auth Update Username for the SQL Server")]
        [string]$sqlAuthUpdateUsername,
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter the SQL Auth Update Password for the SQL Server")]
        [string]$sqlAuthUpdateUserPassword
    )

    $secureSqlAuthUpdateUserPassword = ConvertTo-SecureString $sqlAuthUpdateUserPassword -AsPlainText
    $sqlAdminCredentials = New-Object System.Management.Automation.PSCredential ($sqlAuthUpdateUsername, $secureSqlAuthUpdateUserPassword)

    Return $sqlAdminCredentials
}

Function Get-SqlServerInstanceAddress {
    param(
        [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter the IP address for the SQL Server")]
        [string]$sqlServerIpAddress
    )

    $serverInstanceAddress = $sqlServerIpAddress + ",14330"

    Return $serverInstanceAddress
}

Function Get-SqlConnectionTimeout {
    $connectionTimeoutInSeconds = 5

    Return $connectionTimeoutInSeconds
}