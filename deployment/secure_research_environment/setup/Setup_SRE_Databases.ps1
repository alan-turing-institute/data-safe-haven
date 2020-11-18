param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -Subscription $config.sre.subscriptionName


# Create database resource group if it does not exist
# ---------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.databases.rg -Location $config.sre.location

# Ensure that VNet exists
# -----------------------
$virtualNetwork = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg


# Create each database defined in the config file
# -----------------------------------------------
foreach ($dbConfigName in $config.sre.databases.Keys) {
    if ($config.sre.databases[$dbConfigName] -isnot [Hashtable]) { continue }
    $databaseCfg = $config.sre.databases[$dbConfigName]
    $subnetCfg = $config.sre.network.vnet.subnets[$databaseCfg.subnet]

    # Ensure that the NSG for this subnet exists and required rules are set
    # ---------------------------------------------------------------------
    $nsg = Deploy-NetworkSecurityGroup -Name $subnetCfg.nsg.name -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
    $rules = Get-JsonFromMustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "network_rules" $subnetCfg.nsg.rules) -ArrayJoiner '"' -Parameters $config -AsHashtable
    $null = Set-NetworkSecurityGroupRules -NetworkSecurityGroup $nsg -Rules $rules

    # Ensure that subnet exists and that the NSG is attached
    # ------------------------------------------------------
    $subnet = Deploy-Subnet -Name $subnetCfg.name -VirtualNetwork $virtualNetwork -AddressPrefix $subnetCfg.cidr
    $subnet = Set-SubnetNetworkSecurityGroup -Subnet $subnet -NetworkSecurityGroup $nsg -VirtualNetwork $virtualNetwork

    try {
        # Temporarily allow outbound internet during deployment
        # -----------------------------------------------------
        Add-LogMessage -Level Warning "Temporarily allowing outbound internet access from $($databaseCfg.ip)..."
        Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                                     -Name "OutboundAllowInternetTemporary" `
                                     -Description "Outbound allow internet" `
                                     -Priority 100 `
                                     -Direction Outbound `
                                     -Access Allow -Protocol * `
                                     -SourceAddressPrefix $databaseCfg.ip `
                                     -SourcePortRange * `
                                     -DestinationAddressPrefix Internet `
                                     -DestinationPortRange *

        # Retrieve common secrets from key vaults
        # ---------------------------------------
        Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
        $dbAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $databaseCfg.dbAdminPasswordSecretName -DefaultLength 20
        $domainJoinPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.dataServers.passwordSecretName -DefaultLength 20
        $vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
        $vmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $databaseCfg.adminPasswordSecretName -DefaultLength 20

        # Deploy an SQL server
        # --------------------
        if ($databaseCfg.type -eq "MSSQL") {
            # Retrieve secrets from key vaults
            Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.shm.keyVault.name)'..."
            Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
            $dbAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $databaseCfg.dbAdminUsernameSecretName -DefaultValue "sre$($config.sre.id)sqlauthupd".ToLower()

            # Create SQL server from template
            Add-LogMessage -Level Info "Preparing to create SQL database $($databaseCfg.vmName) from template..."
            $params = @{
                Administrator_Password       = (ConvertTo-SecureString $vmAdminPassword -AsPlainText -Force)
                Administrator_User           = $vmAdminUsername
                BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
                Data_Disk_Size               = $databaseCfg.disks.data.sizeGb
                Data_Disk_Type               = $databaseCfg.disks.data.type
                Db_Admin_Password            = $dbAdminPassword  # NB. This has to be in plaintext for the deployment to work correctly
                Db_Admin_Username            = $dbAdminUsername
                Domain_Join_Password         = (ConvertTo-SecureString $domainJoinPassword -AsPlainText -Force)
                Domain_Join_Username         = $config.shm.users.computerManagers.dataServers.samAccountName
                Domain_Name                  = $config.shm.domain.fqdn
                IP_Address                   = $databaseCfg.ip
                OU_Path                      = $config.shm.domain.ous.dataServers.path
                OS_Disk_Size                 = $databaseCfg.disks.os.sizeGb
                OS_Disk_Type                 = $databaseCfg.disks.os.type
                Sql_Connection_Port          = $databaseCfg.port
                Sql_Server_Name              = $databaseCfg.vmName
                Sql_Server_Edition           = $databaseCfg.sku
                SubnetResourceId             = $subnet.Id
                VM_Size                      = $databaseCfg.vmSize
            }
            Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-mssql2019-server-template.json") -Params $params -ResourceGroupName $config.sre.databases.rg

            # Set locale, install updates and reboot
            Add-LogMessage -Level Info "Updating $($databaseCfg.vmName)..."  # NB. this takes around 20 minutes due to a large SQL server update
            Invoke-WindowsConfigureAndUpdate -VMName $databaseCfg.vmName -ResourceGroupName $config.sre.databases.rg -TimeZone $config.sre.time.timezone.windows -NtpServer $config.shm.time.ntp.poolFqdn -AdditionalPowershellModules @("SqlServer")

            # Lockdown SQL server
            Add-LogMessage -Level Info "[ ] Locking down $($databaseCfg.vmName)..."
            $serverLockdownCommandPath = (Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "sre-mssql2019-server-lockdown.sql")
            $params = @{
                DataAdminGroup           = "`"$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.dataAdministrators.name)`""
                DbAdminPassword          = $dbAdminPassword
                DbAdminUsername          = $dbAdminUsername
                EnableSSIS               = $databaseCfg.enableSSIS
                ResearchUsersGroup       = "`"$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.researchUsers.name)`""
                ServerLockdownCommandB64 = [Convert]::ToBase64String((Get-Content $serverLockdownCommandPath -Raw -AsByteStream))
                SysAdminGroup            = "`"$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.systemAdministrators.name)`""
                VmAdminUsername          = $vmAdminUsername
            }
            $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "Lockdown_Sql_Server.ps1"
            $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $databaseCfg.vmName -ResourceGroupName $config.sre.databases.rg -Parameter $params
            Write-Output $result.Value

        # Deploy a PostgreSQL server
        # --------------------------
        } elseif ($databaseCfg.type -eq "PostgreSQL") {
            # Create PostgreSQL server from template
            Add-LogMessage -Level Info "Preparing to create PostgreSQL database $($databaseCfg.vmName)..."

            # Retrieve secrets from key vaults
            Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
            $dbServiceAccountName = $config.sre.users.serviceAccounts.postgres.name
            $dbServiceAccountSamAccountName = $config.sre.users.serviceAccounts.postgres.samAccountName
            $dbServiceAccountPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.postgres.passwordSecretName -DefaultLength 20
            $ldapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20

            # Create an AD service principal and get the keytab for it
            Add-LogMessage -Level Info "Register '$dbServiceAccountName' ($dbServiceAccountSamAccountName) as a service principal for the database..."
            $null = Set-AzContext -Subscription $config.shm.subscriptionName
            $params = @{
                Hostname       = "`"$($databaseCfg.vmName)`""
                Name           = "`"$($dbServiceAccountName)`""
                SamAccountName = "`"$($dbServiceAccountSamAccountName)`""
                ShmFqdn        = "`"$($config.shm.domain.fqdn)`""
            }
            $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "Create_Postgres_Service_Principal.ps1"
            $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
            Write-Output $result.Value
            $null = Set-AzContext -Subscription $config.sre.subscriptionName

            # Deploy NIC and data disks
            $bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
            $vmNic = Deploy-VirtualMachineNIC -Name "$($databaseCfg.vmName)-NIC" -ResourceGroupName $config.sre.databases.rg -Subnet $subnet -PrivateIpAddress $databaseCfg.ip -Location $config.sre.location
            $dataDisk = Deploy-ManagedDisk -Name "$($databaseCfg.vmName)-DATA-DISK" -SizeGB $databaseCfg.disks.data.sizeGb -Type $databaseCfg.disks.data.type -ResourceGroupName $config.sre.databases.rg -Location $config.sre.location

            # Construct the cloud-init file
            Add-LogMessage -Level Info "Constructing cloud-init from template..."
            $cloudInitTemplate = Get-Content $(Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-postgres-vm.template.yaml" -Resolve) -Raw

            # Insert scripts into the cloud-init file
            $resourcePaths = @()
            $resourcePaths += @("krb5.conf") | ForEach-Object { Join-Path $PSScriptRoot ".." "cloud_init" "resources" $_ }
            $resourcePaths += @("join_domain.sh") | ForEach-Object { Join-Path $PSScriptRoot ".." "cloud_init" "scripts" $_ }
            foreach ($resourcePath in $resourcePaths) {
                $resourceFileName = $resourcePath | Split-Path -Leaf
                $indent = $cloudInitTemplate -split "`n" | Where-Object { $_ -match "<${resourceFileName}>" } | ForEach-Object { $_.Split("<")[0] } | Select-Object -First 1
                $indentedContent = (Get-Content $resourcePath -Raw) -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
                $cloudInitTemplate = $cloudInitTemplate.Replace("${indent}<${resourceFileName}>", $indentedContent)
            }

            # Expand placeholders in the cloud-init file
            $cloudInitTemplate = $cloudInitTemplate.
                Replace("<client-cidr>", $config.sre.network.vnet.subnets.compute.cidr).
                Replace("<db-admin-password>", $dbAdminPassword).
                Replace("<db-data-admin-group>", $config.sre.domain.securityGroups.dataAdministrators.name).
                Replace("<db-sysadmin-group>", $config.sre.domain.securityGroups.systemAdministrators.name).
                Replace("<db-users-group>", $config.sre.domain.securityGroups.researchUsers.name).
                Replace("<domain-join-username>", $config.shm.users.computerManagers.dataServers.samAccountName).
                Replace("<domain-join-password>", $domainJoinPassword).
                Replace("<ldap-group-filter>", "(&(objectClass=group)(|(CN=SG $($config.sre.domain.netbiosName) *)(CN=$($config.shm.domain.securityGroups.serverAdmins.name))))").  # Using ' *' removes the risk of synchronising groups from an SRE with an overlapping name
                Replace("<ldap-groups-base-dn>", $config.shm.domain.ous.securityGroups.path).
                Replace("<ldap-postgres-service-account-dn>", "CN=${dbServiceAccountName},$($config.shm.domain.ous.serviceAccounts.path)").
                Replace("<ldap-postgres-service-account-password>", $dbServiceAccountPassword).
                Replace("<ldap-search-user-dn>", "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)").
                Replace("<ldap-search-user-password>", $ldapSearchPassword).
                Replace("<ldap-user-filter>", "(&(objectClass=user)(|(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path))(memberOf=CN=$($config.shm.domain.securityGroups.serverAdmins.name),$($config.shm.domain.ous.securityGroups.path))))").
                Replace("<ldap-users-base-dn>", $config.shm.domain.ous.researchUsers.path).
                Replace("<ntp-server>", $config.shm.time.ntp.poolFqdn).
                Replace("<ou-data-servers-path>", $config.shm.domain.ous.dataServers.path).
                Replace("<shm-dc-hostname>", $config.shm.dc.hostname).
                Replace("<shm-dc-hostname-upper>", $($config.shm.dc.hostname).ToUpper()).
                Replace("<shm-fqdn-lower>", $($config.shm.domain.fqdn).ToLower()).
                Replace("<shm-fqdn-upper>", $($config.shm.domain.fqdn).ToUpper()).
                Replace("<timezone>", $config.sre.time.timezone.linux).
                Replace("<vm-hostname>", $databaseCfg.vmName).
                Replace("<vm-ipaddress>", $databaseCfg.ip)

            # Deploy the VM
            $params = @{
                AdminPassword          = $vmAdminPassword
                AdminUsername          = $vmAdminUsername
                BootDiagnosticsAccount = $bootDiagnosticsAccount
                CloudInitYaml          = $cloudInitTemplate
                DataDiskIds            = @($dataDisk.Id)
                ImageSku               = $databaseCfg.sku
                Location               = $config.sre.location
                Name                   = $databaseCfg.vmName
                NicId                  = $vmNic.Id
                OsDiskType             = $databaseCfg.disks.os.type
                ResourceGroupName      = $config.sre.databases.rg
                Size                   = $databaseCfg.vmSize
            }
            $null = Deploy-UbuntuVirtualMachine @params
            Enable-AzVM -Name $databaseCfg.vmName -ResourceGroupName $config.sre.databases.rg
        }


    } finally {
        # Remove temporary NSG rules
        Add-LogMessage -Level Warning "Removing temporary outbound internet access from $($databaseCfg.ip)..."
        $null = Remove-AzNetworkSecurityRuleConfig -Name "OutboundAllowInternetTemporary" -NetworkSecurityGroup $nsg
        $null = $nsg | Set-AzNetworkSecurityGroup
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
