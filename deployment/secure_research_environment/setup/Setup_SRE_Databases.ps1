param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $false, HelpMessage = "Force an existing database VM to be redeployed.")]
    [switch]$Redeploy
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -Subscription $config.sre.subscriptionName -ErrorAction Stop


# Create database resource group if it does not exist
# ---------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.databases.rg -Location $config.sre.location


# Ensure that VNet and deployment subnet exist
# --------------------------------------------
Add-LogMessage -Level Info "Retrieving virtual network '$($config.sre.network.vnet.name)'..."
$virtualNetwork = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
$deploymentSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.deployment.name -VirtualNetworkName $virtualNetwork.Name -ResourceGroupName $config.sre.network.vnet.rg


# Create each database defined in the config file
# -----------------------------------------------
foreach ($keyName in $config.sre.databases.Keys) {
    if ($config.sre.databases[$keyName] -isnot [System.Collections.IDictionary]) { continue }
    $databaseCfg = $config.sre.databases[$keyName]

    # Check whether this database VM has already been deployed
    # --------------------------------------------------------
    if (Get-AzVM -Name $databaseCfg.vmName -ResourceGroupName $config.sre.databases.rg -ErrorAction SilentlyContinue) {
        if ($Redeploy) {
            Add-LogMessage -Level Info "Removing existing database VM '$($databaseCfg.vmName)'..."
            $null = Remove-VirtualMachine -Name $databaseCfg.vmName -ResourceGroupName $config.sre.databases.rg -Force
            if ($?) {
                Add-LogMessage -Level Success "Removal of database VM '$($databaseCfg.vmName)' succeeded"
            } else {
                Add-LogMessage -Level Fatal "Removal of database VM '$($databaseCfg.vmName)' failed!"
            }
        } else {
            Add-LogMessage -Level Warning "Database VM '$($databaseCfg.vmName)' already exists. Use the '-Redeploy' option if you want to remove the existing database and its data and deploy a new one."
            continue
        }
    }

    # Get database subnet and deployment IP address
    # ---------------------------------------------
    $subnetCfg = $config.sre.network.vnet.subnets[$databaseCfg.subnet]
    $subnet = Deploy-Subnet -Name $subnetCfg.name -VirtualNetwork $virtualNetwork -AddressPrefix $subnetCfg.cidr
    $deploymentIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.deployment.cidr -VirtualNetwork $virtualNetwork -Verbose

    # Retrieve domain join details from SHM Key Vault
    # -----------------------------------------------
    $null = Set-AzContext -Subscription $config.shm.subscriptionName -ErrorAction Stop
    Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.shm.keyVault.name)'..."
    $domainJoinPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.databaseServers.passwordSecretName -DefaultLength 20 -AsPlaintext
    $null = Set-AzContext -Subscription $config.sre.subscriptionName -ErrorAction Stop

    # Retrieve usernames/passwords from SRE Key Vault
    # -----------------------------------------------
    Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.sre.keyVault.name)'..."
    $dbAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $databaseCfg.dbAdminUsernameSecretName -AsPlaintext
    $dbAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $databaseCfg.dbAdminPasswordSecretName -DefaultLength 20 -AsPlaintext
    $vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext
    $vmAdminPasswordSecure = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $databaseCfg.adminPasswordSecretName -DefaultLength 20

    # Deploy an SQL server
    # --------------------
    if ($databaseCfg.type -eq "MSSQL") {
        # Create SQL server from template
        Add-LogMessage -Level Info "Preparing to create SQL database $($databaseCfg.vmName) from template..."
        $params = @{
            Administrator_Password       = $vmAdminPasswordSecure
            Administrator_User           = $vmAdminUsername
            BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
            Data_Disk_Size               = $databaseCfg.disks.data.sizeGb
            Data_Disk_Type               = $databaseCfg.disks.data.type
            Db_Admin_Password            = $dbAdminPassword  # NB. This has to be in plaintext for the deployment to work correctly
            Db_Admin_Username            = $dbAdminUsername
            IP_Address                   = $deploymentIpAddress
            OS_Disk_Size                 = $databaseCfg.disks.os.sizeGb
            OS_Disk_Type                 = $databaseCfg.disks.os.type
            Sql_Connection_Port          = $databaseCfg.port
            Sql_Server_Name              = $databaseCfg.vmName
            Sql_Server_Edition           = $databaseCfg.sku
            SubnetResourceId             = $deploymentSubnet.Id
            VM_Size                      = $databaseCfg.vmSize
        }
        Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-mssql2019-server-template.json") -Params $params -ResourceGroupName $config.sre.databases.rg

        # Set locale, install updates and reboot
        Add-LogMessage -Level Info "Updating $($databaseCfg.vmName)..."
        Invoke-WindowsConfigureAndUpdate -VMName $databaseCfg.vmName -ResourceGroupName $config.sre.databases.rg -TimeZone $config.sre.time.timezone.windows -NtpServer $config.shm.time.ntp.poolFqdn -AdditionalPowershellModules @("SqlServer")

        # Change subnets and IP address while the VM is off
        Update-VMIpAddress -Name $databaseCfg.vmName -ResourceGroupName $config.sre.databases.rg -Subnet $subnet -IpAddress $databaseCfg.ip

        # Join the VM to the domain and restart it
        Add-WindowsVMtoDomain -Name $databaseCfg.vmName `
                              -ResourceGroupName $config.sre.databases.rg `
                              -DomainName $config.shm.domain.fqdn `
                              -DomainJoinUsername $config.shm.users.computerManagers.databaseServers.samAccountName `
                              -DomainJoinPassword (ConvertTo-SecureString $domainJoinPassword -AsPlainText -Force) `
                              -OUPath $config.shm.domain.ous.databaseServers.path `
                              -ForceRestart

        # Lockdown SQL server
        Add-LogMessage -Level Info "[ ] Locking down $($databaseCfg.vmName)..."
        $serverLockdownCommandPath = (Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "sre-mssql2019-server-lockdown.sql")
        $params = @{
            DataAdminGroup           = "$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.dataAdministrators.name)"
            DbAdminPasswordB64       = $dbAdminPassword | ConvertTo-Base64
            DbAdminUsername          = $dbAdminUsername
            EnableSSIS               = "$($databaseCfg.enableSSIS)"
            ResearchUsersGroup       = "$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.researchUsers.name)"
            ServerLockdownCommandB64 = Get-Content $serverLockdownCommandPath -Raw | ConvertTo-Base64
            SysAdminGroup            = "$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.systemAdministrators.name)"
            VmAdminUsername          = $vmAdminUsername
        }
        $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "Lockdown_Sql_Server.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $databaseCfg.vmName -ResourceGroupName $config.sre.databases.rg -Parameter $params

    # Deploy a PostgreSQL server
    # --------------------------
    } elseif ($databaseCfg.type -eq "PostgreSQL") {
        # Create PostgreSQL server from template
        Add-LogMessage -Level Info "Preparing to create PostgreSQL database $($databaseCfg.vmName)..."

        # Retrieve secrets from Key Vaults
        Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.sre.keyVault.name)'..."
        $dbServiceAccountName = $config.sre.users.serviceAccounts.postgres.name
        $dbServiceAccountSamAccountName = $config.sre.users.serviceAccounts.postgres.samAccountName
        $dbServiceAccountPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.postgres.passwordSecretName -DefaultLength 20 -AsPlaintext
        $ldapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext

        # Create an AD service principal
        Add-LogMessage -Level Info "Register '$dbServiceAccountName' ($dbServiceAccountSamAccountName) as a service principal for the database..."
        $null = Set-AzContext -Subscription $config.shm.subscriptionName -ErrorAction Stop
        $params = @{
            Hostname       = $databaseCfg.vmName
            Name           = "$($dbServiceAccountName)"
            SamAccountName = $dbServiceAccountSamAccountName
            ShmFqdn        = $config.shm.domain.fqdn
        }
        $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "Create_Postgres_Service_Principal.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
        $null = Set-AzContext -Subscription $config.sre.subscriptionName -ErrorAction Stop

        # Deploy NIC and data disk
        $bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
        $networkCard = Deploy-VirtualMachineNIC -Name "$($databaseCfg.vmName)-NIC" -ResourceGroupName $config.sre.databases.rg -Subnet $deploymentSubnet -PrivateIpAddress $deploymentIpAddress -Location $config.sre.location
        $dataDisk = Deploy-ManagedDisk -Name "$($databaseCfg.vmName)-DATA-DISK" -SizeGB $databaseCfg.disks.data.sizeGb -Type $databaseCfg.disks.data.type -ResourceGroupName $config.sre.databases.rg -Location $config.sre.location

        # Construct the cloud-init file
        Add-LogMessage -Level Info "Constructing cloud-init from template..."
        $cloudInitTemplate = Get-Content $(Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-postgres-vm.template.yaml" -Resolve) -Raw

        # Insert additional files into the cloud-init template
        foreach ($resource in (Get-ChildItem (Join-Path $PSScriptRoot ".." "cloud_init" "resources"))) {
            $indent = $cloudInitTemplate -split "`n" | Where-Object { $_ -match "<$($resource.Name)>" } | ForEach-Object { $_.Split("<")[0] } | Select-Object -First 1
            $indentedContent = (Get-Content $resource.FullName -Raw) -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
            $cloudInitTemplate = $cloudInitTemplate.Replace("${indent}<$($resource.Name)>", $indentedContent)
        }

        # Expand placeholders in the cloud-init file
        $cloudInitTemplate = $cloudInitTemplate.
            Replace("<client-cidr>", $config.sre.network.vnet.subnets.compute.cidr).
            Replace("<db-admin-password>", $dbAdminPassword).
            Replace("<db-data-admin-group>", $config.sre.domain.securityGroups.dataAdministrators.name).
            Replace("<db-sysadmin-group>", $config.sre.domain.securityGroups.systemAdministrators.name).
            Replace("<db-users-group>", $config.sre.domain.securityGroups.researchUsers.name).
            Replace("<domain-join-username>", $config.shm.users.computerManagers.databaseServers.samAccountName).
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
            Replace("<ou-database-servers-path>", $config.shm.domain.ous.databaseServers.path).
            Replace("<shm-dc-hostname>", $config.shm.dc.hostname).
            Replace("<shm-dc-hostname-upper>", $($config.shm.dc.hostname).ToUpper()).
            Replace("<shm-fqdn-lower>", $($config.shm.domain.fqdn).ToLower()).
            Replace("<shm-fqdn-upper>", $($config.shm.domain.fqdn).ToUpper()).
            Replace("<timezone>", $config.sre.time.timezone.linux).
            Replace("<vm-hostname>", $databaseCfg.vmName).
            Replace("<vm-ipaddress>", $databaseCfg.ip)

        # Deploy the VM
        $params = @{
            AdminPassword          = $vmAdminPasswordSecure
            AdminUsername          = $vmAdminUsername
            BootDiagnosticsAccount = $bootDiagnosticsAccount
            CloudInitYaml          = $cloudInitTemplate
            DataDiskIds            = @($dataDisk.Id)
            ImageSku               = $databaseCfg.sku
            Location               = $config.sre.location
            Name                   = $databaseCfg.vmName
            NicId                  = $networkCard.Id
            OsDiskType             = $databaseCfg.disks.os.type
            ResourceGroupName      = $config.sre.databases.rg
            Size                   = $databaseCfg.vmSize
        }
        $null = Deploy-UbuntuVirtualMachine @params

        # Change subnets and IP address while the VM is off - note that the domain join will happen on restart
        Update-VMIpAddress -Name $databaseCfg.vmName -ResourceGroupName $config.sre.databases.rg -Subnet $subnet -IpAddress $databaseCfg.ip
        # Update DNS records for this VM
        Update-VMDnsRecords -DcName $config.shm.dc.vmName -DcResourceGroupName $config.shm.dc.rg -ShmFqdn $config.shm.domain.fqdn -ShmSubscriptionName $config.shm.subscriptionName -VmHostname $databaseCfg.vmName -VmIpAddress $databaseCfg.ip
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
