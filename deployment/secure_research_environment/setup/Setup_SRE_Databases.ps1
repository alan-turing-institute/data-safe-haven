param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
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
foreach ($dbConfig in $config.sre.databases.psobject.Members) {
    if ($dbConfig.TypeNameOfValue -ne "System.Management.Automation.PSCustomObject") { continue }
    $databaseCfg = $dbConfig.Value
    $subnetCfg = $config.sre.network.subnets.($databaseCfg.subnet)
    $nsgCfg = $config.sre.network.nsg.($subnetCfg.nsg)

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
        $privateIpAddress = "$($subnetCfg.prefix).$($databaseCfg.ipLastOctet)"
        Add-LogMessage -Level Warning "Temporarily allowing outbound internet access from $privateIpAddress..."
        Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                                     -Name "OutboundAllowInternetTemporary" `
                                     -Description "Outbound allow internet" `
                                     -Priority 100 `
                                     -Direction Outbound -Access Allow -Protocol * `
                                     -SourceAddressPrefix $privateIpAddress -SourcePortRange * `
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
            $shmDcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminPassword
            $shmDcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.shm.id)admin".ToLower()
            Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
            $sqlAuthUpdateUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUserPassword
            $sqlAuthUpdateUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUsername -DefaultValue "sre$($config.sre.id)sqlauthupd".ToLower()
            $sqlVmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlVmAdminPassword

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
                IP_Address = $privateIpAddress
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
                ServerLockdownCommandB64 = [Convert]::ToBase64String((Get-Content $serverLockdownCommandPath -Raw -AsByteStream))
                SqlAdminGroup = "$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.sqlAdmins.name)"
                SqlAuthUpdateUserPassword = $sqlAuthUpdateUserPassword
                SqlAuthUpdateUsername = $sqlAuthUpdateUsername
                SreResearchUsersGroup = "$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.researchUsers.name)"
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
            $postgresDbAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.postgresDbAdminPassword
            $postgresDbServiceAccountName = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.postgresDbServiceAccountUsername -DefaultValue "sre$($config.sre.id)pgdbsa"
            $postgresDbServiceAccountPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.postgresDbServiceAccountPassword
            $postgresVmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.postgresVmAdminPassword
            $postgresVmLdapPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.postgresVmLdapPassword

            # Create an AD service principal and get the keytab for it
            Add-LogMessage -Level Info "Create a service principal for the database ($PostgresDbServiceAccountName) and get its keytab..."
            $_ = Set-AzContext -Subscription $config.shm.subscriptionName
            $params = @{
                PostgresDbServiceAccountName = "`"$($PostgresDbServiceAccountName)`""
                PostgresDbServiceAccountPassword = "`"$($PostgresDbServiceAccountPassword)`""
                PostgresVmHostname = "`"$($databaseCfg.name)`""
                ServiceOuPath = "`"$($config.shm.domain.serviceOuPath)`""
                ShmFqdn = "`"$($config.shm.domain.fqdn)`""
                SreNetbiosName = "`"$($config.sre.domain.netbiosName)`""
            }
            $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "Create_Postgres_Service_Principal.ps1"
            $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
            Write-Output $result.Value
            $_ = Set-AzContext -Subscription $config.sre.subscriptionName

            # Deploy NIC and data disks
            $bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
            $vmNic = Deploy-VirtualMachineNIC -Name "$($databaseCfg.name)-NIC" -ResourceGroupName $config.sre.databases.rg -Subnet $subnet -PrivateIpAddress $privateIpAddress -Location $config.sre.location
            $dataDisk = Deploy-ManagedDisk -Name "$($databaseCfg.name)-DATA-DISK" -SizeGB $databaseCfg.datadisk.size_gb -Type $databaseCfg.datadisk.type -ResourceGroupName $config.sre.databases.rg -Location $config.sre.location

            # Construct the cloud-init file
            Add-LogMessage -Level Info "Constructing cloud-init from template..."
            $cloudInitTemplate = Get-Content $(Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-postgres-vm.template.yaml" -Resolve) -Raw
            $cloudInitTemplate = $cloudInitTemplate.Replace("<client-cidr>", $config.sre.network.subnets.data.cidr).
                                                    Replace("<db-admin-group>", $config.sre.domain.securityGroups.sqlAdmins.name).
                                                    Replace("<db-vm-hostname>", $databaseCfg.name).
                                                    Replace("<db-vm-ipaddress>", $privateIpAddress).
                                                    Replace("<db-users-group>", $config.sre.domain.securityGroups.researchUsers.Name).
                                                    Replace("<ldap-bind-dn>", "CN=$($config.sre.users.ldap.postgresdb.Name),$($config.shm.domain.serviceOuPath)").
                                                    Replace("<ldap-bind-passwd>", $postgresVmLdapPassword).
                                                    Replace("<ldap-group-filter>", "(&(objectClass=group)(CN=SG $($config.sre.domain.netbiosName)*))").
                                                    Replace("<ldap-groups-base-dn>", $config.shm.domain.securityOuPath).
                                                    Replace("<ldap-user-filter>", "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.Name),$($config.shm.domain.securityOuPath)))").
                                                    Replace("<ldap-users-base-dn>", $config.shm.domain.userOuPath).
                                                    Replace("<postgres-admin-user-password>", $postgresDbAdminPassword).
                                                    Replace("<postgres-ldap-username>", $config.sre.users.ldap.postgresdb.samAccountName).
                                                    Replace("<postgres-service-account-password>", $PostgresDbServiceAccountPassword).
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
        Add-LogMessage -Level Info "Removing temporary outbound internet access from $privateIpAddress..."
        $_ = Remove-AzNetworkSecurityRuleConfig -Name "OutboundAllowInternetTemporary" -NetworkSecurityGroup $nsg
        $_ = $nsg | Set-AzNetworkSecurityGroup
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
