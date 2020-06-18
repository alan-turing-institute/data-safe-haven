param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$_ = Set-AzContext -Subscription $config.sre.subscriptionName


# Create database resource group if it does not exist
# ---------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.databases.rg -Location $config.sre.location

# Ensure that VNet exists
# -----------------------
$virtualNetwork = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg


# Create each database defined in the config file
# -----------------------------------------------
foreach ($dbConfigName in $config.sre.databases.Keys) {
    if ($config.sre.databases[$dbConfigName] -isnot [Hashtable]) { continue }
    $databaseCfg = $config.sre.databases[$dbConfigName]
    $subnetCfg = $config.sre.network.subnets[$databaseCfg.subnet]
    $nsgCfg = $config.sre.network.nsg[$subnetCfg.nsg]

    # Ensure that subnet exists
    # -------------------------
    $subnet = Deploy-Subnet -Name $subnetCfg.name -VirtualNetwork $virtualNetwork -AddressPrefix $subnetCfg.cidr


    # Set up the NSG for this subnet
    # ------------------------------
    $nsg = Deploy-NetworkSecurityGroup -Name $nsgCfg.name -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
    Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                                 -Name "InboundAllowVNet" `
                                 -Description "Inbound allow SRE VNet" `
                                 -Priority 3000 `
                                 -Direction Inbound -Access Allow -Protocol * `
                                 -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                                 -DestinationAddressPrefix $subnetCfg.cidr -DestinationPortRange *
    Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                                 -Name "InboundDenyAll" `
                                 -Description "Inbound deny all" `
                                 -Priority 4000 `
                                 -Direction Inbound -Access Deny -Protocol * `
                                 -SourceAddressPrefix * -SourcePortRange * `
                                 -DestinationAddressPrefix * -DestinationPortRange *
    Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                                 -Name "OutboundDenyInternet" `
                                 -Description "Outbound deny internet" `
                                 -Priority 4000 `
                                 -Direction Outbound -Access Deny -Protocol * `
                                 -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                                 -DestinationAddressPrefix Internet -DestinationPortRange *

    # Attach the NSG to the appropriate subnet
    # ----------------------------------------
    $_ = Set-SubnetNetworkSecurityGroup -Subnet $subnet -NetworkSecurityGroup $nsg -VirtualNetwork $virtualNetwork


    try {
        # Temporarily allow outbound internet during deployment
        # -----------------------------------------------------
        Add-LogMessage -Level Warning "Temporarily allowing outbound internet access from $($databaseCfg.ip)..."
        Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                                     -Name "OutboundAllowInternetTemporary" `
                                     -Description "Outbound allow internet" `
                                     -Priority 100 `
                                     -Direction Outbound -Access Allow -Protocol * `
                                     -SourceAddressPrefix $databaseCfg.ip -SourcePortRange * `
                                     -DestinationAddressPrefix Internet -DestinationPortRange *

        # Retrieve common secrets from key vaults
        # ---------------------------------------
        Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
        $sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()


        # Deploy an SQL server
        # --------------------
        if ($databaseCfg.type -eq "MSSQL") {
            # Retrieve secrets from key vaults
            Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.shm.keyVault.name)'..."
            $shmDcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminPassword -DefaultLength 20
            $shmDcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.shm.id)admin".ToLower()
            Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
            $sqlAuthUpdateUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUserPassword -DefaultLength 20
            $sqlAuthUpdateUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUsername -DefaultValue "sre$($config.sre.id)sqlauthupd".ToLower()
            $sqlVmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlVmAdminPassword -DefaultLength 20

            # Create SQL server from template
            Add-LogMessage -Level Info "Preparing to create SQL database $($databaseCfg.name) from template..."
            $params = @{
                Administrator_Password = (ConvertTo-SecureString $sqlVmAdminPassword -AsPlainText -Force)
                Administrator_User = $sreAdminUsername
                BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
                Data_Disk_Size = $databaseCfg.datadisk.size_gb
                Data_Disk_Type = $databaseCfg.datadisk.type
                DC_Join_Password = (ConvertTo-SecureString $shmDcAdminPassword -AsPlainText -Force)
                DC_Join_User = $shmDcAdminUsername
                Domain_Name = $config.shm.domain.fqdn
                IP_Address = $databaseCfg.ip
                Location = $config.sre.location
                OS_Disk_Size = $databaseCfg.osdisk.size_gb
                OS_Disk_Type = $databaseCfg.osdisk.type
                Sql_AuthUpdate_UserName = $sqlAuthUpdateUsername
                Sql_AuthUpdate_Password = $sqlAuthUpdateUserPassword  # NB. This has to be in plaintext for the deployment to work correctly
                Sql_Connection_Port = $databaseCfg.port
                Sql_Server_Name = $databaseCfg.name
                Sql_Server_Edition = $databaseCfg.sku
                SubnetResourceId = $subnet.Id
                VM_Size = $databaseCfg.vmSize
            }
            Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-mssql2019-server-template.json") -Params $params -ResourceGroupName $config.sre.databases.rg

            # Set locale, install updates and reboot
            Add-LogMessage -Level Info "Updating $($databaseCfg.name)..."  # NB. this takes around 20 minutes due to a large SQL server update
            Invoke-WindowsConfigureAndUpdate -VMName $databaseCfg.name -ResourceGroupName $config.sre.databases.rg -AdditionalPowershellModules @("SqlServer")

            # Lockdown SQL server
            Add-LogMessage -Level Info "[ ] Locking down $($databaseCfg.name)..."
            $serverLockdownCommandPath = (Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "sre-mssql2019-server-lockdown.sql")
            $params = @{
                EnableSSIS = $databaseCfg.enableSSIS
                LocalAdminUser = $sreAdminUsername
                DataAdminGroup = "$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.dataAdministrators.name)"
                ResearchUsersGroup = "$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.researchUsers.name)"
                SysAdminGroup = "$($config.shm.domain.netbiosName)\$($config.shm.domain.securityGroups.serverAdmins.name)"
                ServerLockdownCommandB64 = [Convert]::ToBase64String((Get-Content $serverLockdownCommandPath -Raw -AsByteStream))
                SqlAuthUpdateUserPassword = $sqlAuthUpdateUserPassword
                SqlAuthUpdateUsername = $sqlAuthUpdateUsername
            }
            $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "Lockdown_Sql_Server.ps1"
            $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $databaseCfg.name -ResourceGroupName $config.sre.databases.rg -Parameter $params
            Write-Output $result.Value

        # Deploy a PostgreSQL server
        # --------------------------
        } elseif ($databaseCfg.type -eq "PostgreSQL") {
            # Create PostgreSQL server from template
            Add-LogMessage -Level Info "Preparing to create PostgreSQL database $($databaseCfg.name)..."

            # Retrieve secrets from key vaults
            Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
            $postgresDbAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.postgresDbAdminUsername -DefaultValue "postgres" # This is recorded for auditing purposes - changing it will not change the username of the admin account
            $postgresDbAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.postgresDbAdminPassword -DefaultLength 20
            $postgresDbServiceAccountName = $config.sre.users.serviceAccounts.postgres.name
            $postgresDbServiceAccountSamAccountName = $config.sre.users.serviceAccounts.postgres.samAccountName
            $postgresDbServiceAccountPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.postgres.passwordSecretName -DefaultLength 20
            $postgresVmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.postgresVmAdminPassword -DefaultLength 20
            $postgresVmLdapPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.computerManagers.postgres.passwordSecretName -DefaultLength 20

            # Create an AD service principal and get the keytab for it
            Add-LogMessage -Level Info "Register '$postgresDbServiceAccountName' ($postgresDbServiceAccountSamAccountName) as a service principal for the database..."
            $_ = Set-AzContext -Subscription $config.shm.subscriptionName
            $params = @{
                Hostname = "`"$($databaseCfg.name)`""
                Name = "`"$($postgresDbServiceAccountName)`""
                SamAccountName = "`"$($postgresDbServiceAccountSamAccountName)`""
                ShmFqdn = "`"$($config.shm.domain.fqdn)`""
            }
            $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "Create_Postgres_Service_Principal.ps1"
            $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
            Write-Output $result.Value
            $_ = Set-AzContext -Subscription $config.sre.subscriptionName

            # Deploy NIC and data disks
            $bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
            $vmNic = Deploy-VirtualMachineNIC -Name "$($databaseCfg.name)-NIC" -ResourceGroupName $config.sre.databases.rg -Subnet $subnet -PrivateIpAddress $databaseCfg.ip -Location $config.sre.location
            $dataDisk = Deploy-ManagedDisk -Name "$($databaseCfg.name)-DATA-DISK" -SizeGB $databaseCfg.datadisk.size_gb -Type $databaseCfg.datadisk.type -ResourceGroupName $config.sre.databases.rg -Location $config.sre.location

            # Construct the cloud-init file
            Add-LogMessage -Level Info "Constructing cloud-init from template..."
            $cloudInitTemplate = Get-Content $(Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-postgres-vm.template.yaml" -Resolve) -Raw
            $cloudInitTemplate = $cloudInitTemplate.Replace("<client-cidr>", $config.sre.network.subnets.data.cidr).
                                                    Replace("<db-sysadmin-group>", $config.sre.domain.securityGroups.systemAdministrators.name).
                                                    Replace("<db-data-admin-group>", $config.sre.domain.securityGroups.dataAdministrators.name).
                                                    Replace("<db-local-admin-password>", $postgresDbAdminPassword).
                                                    Replace("<db-vm-hostname>", $databaseCfg.name).
                                                    Replace("<db-vm-ipaddress>", $databaseCfg.ip).
                                                    Replace("<db-users-group>", $config.sre.domain.securityGroups.researchUsers.name).
                                                    Replace("<ldap-bind-user-dn>", "CN=$($config.sre.users.computerManagers.postgres.name),$($config.shm.domain.serviceOuPath)").
                                                    Replace("<ldap-bind-user-password>", $postgresVmLdapPassword).
                                                    Replace("<ldap-bind-user-username>", $config.sre.users.computerManagers.postgres.samAccountName).
                                                    Replace("<ldap-group-filter>", "(&(objectClass=group)(|(CN=SG $($config.sre.domain.netbiosName) *)(CN=$($config.shm.domain.securityGroups.serverAdmins.name))))").  # Using ' *' removes the risk of synchronising groups from an SRE with an overlapping name
                                                    Replace("<ldap-groups-base-dn>", $config.shm.domain.securityOuPath).
                                                    Replace("<ldap-postgres-service-account-dn>", "CN=${postgresDbServiceAccountName},$($config.shm.domain.serviceOuPath)").
                                                    Replace("<ldap-postgres-service-account-password>", $postgresDbServiceAccountPassword).
                                                    Replace("<ldap-user-filter>", "(&(objectClass=user)(|(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.securityOuPath))(memberOf=CN=$($config.shm.domain.securityGroups.serverAdmins.name),$($config.shm.domain.securityOuPath))))").
                                                    Replace("<ldap-users-base-dn>", $config.shm.domain.userOuPath).
                                                    Replace("<shm-dc-hostname>", $config.shm.dc.hostname).
                                                    Replace("<shm-dc-hostname-upper>", $($config.shm.dc.hostname).ToUpper()).
                                                    Replace("<shm-fqdn-lower>", $($config.shm.domain.fqdn).ToLower()).
                                                    Replace("<shm-fqdn-upper>", $($config.shm.domain.fqdn).ToUpper())

            # Deploy the VM
            $params = @{
                AdminPassword = $postgresVmAdminPassword
                AdminUsername = $sreAdminUsername
                BootDiagnosticsAccount = $bootDiagnosticsAccount
                CloudInitYaml = $cloudInitTemplate
                DataDiskIds = @($dataDisk.Id)
                ImageSku = $databaseCfg.sku
                Location = $config.sre.location
                Name = $databaseCfg.name
                NicId = $vmNic.Id
                OsDiskType = $databaseCfg.osdisk.type
                ResourceGroupName = $config.sre.databases.rg
                Size = $databaseCfg.vmSize
            }
            $_ = Deploy-UbuntuVirtualMachine @params
            Wait-ForAzVMCloudInit -Name $databaseCfg.name -ResourceGroupName $config.sre.databases.rg
            Enable-AzVM -Name $databaseCfg.name -ResourceGroupName $config.sre.databases.rg
        }


    } finally {
        # Remove temporary NSG rules
        Add-LogMessage -Level Info "Removing temporary outbound internet access from $($databaseCfg.ip)..."
        $_ = Remove-AzNetworkSecurityRuleConfig -Name "OutboundAllowInternetTemporary" -NetworkSecurityGroup $nsg
        $_ = $nsg | Set-AzNetworkSecurityGroup
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
