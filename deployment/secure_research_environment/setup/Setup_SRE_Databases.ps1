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


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$shmDcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.domainAdminPassword
$shmDcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.shm.id)admin".ToLower()
$sreAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dataServerAdminPassword
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$sqlAuthUpdateUserPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUserPassword
$sqlAuthUpdateUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.sqlAuthUpdateUsername -DefaultValue "sre$($config.sre.id)sqlauthupd".ToLower()



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
                                 -SourceAddressPrefix $config.sre.network.vnet.cidr -SourcePortRange * `
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


    # Lockdown SQL server
    # -------------------
    $_ = Set-SubnetNetworkSecurityGroup -Subnet $subnet -NetworkSecurityGroup $nsg -VirtualNetwork $virtualNetwork


    try {
        # Temporarily allow outbound internet during deployment
        # -----------------------------------------------------
        $privateIpAddress = "$($subnetCfg.prefix).$($databaseCfg.ipLastOctet)"
        Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                                    -Name "OutboundAllowInternetTemporary" `
                                    -Description "Outbound allow internet" `
                                    -Priority 100 `
                                    -Direction Outbound -Access Allow -Protocol * `
                                    -SourceAddressPrefix $privateIpAddress -SourcePortRange * `
                                    -DestinationAddressPrefix Internet -DestinationPortRange *


        # Create SQL server from template
        # -------------------------------
        Add-LogMessage -Level Info "Creating $($databaseCfg.name) from template..."
        $params = @{
            Location = $config.sre.location
            Administrator_Password = (ConvertTo-SecureString $sreAdminPassword -AsPlainText -Force)
            Administrator_User = $sreAdminUsername
            DC_Join_Password = (ConvertTo-SecureString $shmDcAdminPassword -AsPlainText -Force)
            DC_Join_User = $shmDcAdminUsername
            Sql_AuthUpdate_UserName = $sqlAuthUpdateUsername
            Sql_AuthUpdate_Password = $sqlAuthUpdateUserPassword  # NB. This has to be in plaintext for the deployment to work correctly
            BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
            Sql_Server_Name = $databaseCfg.name
            Sql_Server_Edition = "sqldev"
            Domain_Name = $config.shm.domain.fqdn
            IP_Address = $privateIpAddress
            SubnetResourceId = $subnet.Id
            VM_Size = $databaseCfg.vmSize
        }
        Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-mssql2019-server-template.json") -Params $params -ResourceGroupName $config.sre.databases.rg


        # Set locale, install updates and reboot
        # --------------------------------------
        Add-LogMessage -Level Info "Updating $($databaseCfg.name)..."  # NB. this takes around 20 minutes due to a large SQL server update
        Invoke-WindowsConfigureAndUpdate -VMName $databaseCfg.name -ResourceGroupName $config.sre.databases.rg -AdditionalPowershellModules @("SqlServer")


        # Lockdown SQL server
        # -------------------
        Add-LogMessage -Level Info "[ ] Locking down $($databaseCfg.name)..."
        $serverLockdownCommandPath = (Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "sre-mssql2019-server-lockdown.sql")
        $params = @{
            EnableSSIS = $databaseCfg.enableSSIS
            SqlAdminGroup = "$($config.shm.domain.netbiosName)\$($config.sre.domain.securityGroups.sqlAdmins.name)"
            SqlAuthUpdateUsername = $sqlAuthUpdateUsername
            SqlAuthUpdateUserPassword = $sqlAuthUpdateUserPassword
            B64ServerLockdownCommand = [Convert]::ToBase64String((Get-Content $serverLockdownCommandPath -Raw -AsByteStream))
        }
        $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_databases" "scripts" "Lockdown_Sql_Server.ps1"
        $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $databaseCfg.name -ResourceGroupName $config.sre.databases.rg -Parameter $params
        Write-Output $result.Value

    } finally {
        # Remove temporary NSG rules
        $_ = Remove-AzNetworkSecurityRuleConfig -Name "OutboundAllowInternetTemporary" -NetworkSecurityGroup $nsg
        $_ = $nsg | Set-AzNetworkSecurityGroup
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
