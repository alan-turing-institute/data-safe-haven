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
$null = Set-AzContext -Subscription $config.sre.subscriptionName


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$domainJoinPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.dataServers.passwordSecretName -DefaultLength 20
$vmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.dataserver.adminPasswordSecretName -DefaultLength 20
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()


# Create data server resource group if it does not exist
# ------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.dataserver.rg -Location $config.sre.location


# Set up the NSG for the data server
# ----------------------------------
$nsg = Deploy-NetworkSecurityGroup -Name $config.sre.dataserver.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "OutboundAllowGoogleNTP" `
                             -Description "Outbound allow connections to Google NTP servers" `
                             -Priority 2200 `
                             -Direction Outbound `
                             -Access Allow `
                             -Protocol * `
                             -SourceAddressPrefix VirtualNetwork `
                             -SourcePortRange * `
                             -DestinationAddressPrefix @("216.239.35.0", "216.239.35.4", "216.239.35.8", "216.239.35.12") `
                             -DestinationPortRange 123
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "Deny_Internet" `
                             -Description "Deny Outbound Internet Access" `
                             -Priority 4000 `
                             -Direction Outbound `
                             -Access Deny `
                             -Protocol * `
                             -SourceAddressPrefix VirtualNetwork `
                             -SourcePortRange * `
                             -DestinationAddressPrefix Internet `
                             -DestinationPortRange *


# Deploy data server from template
# --------------------------------
Add-LogMessage -Level Info "Creating data server '$($config.sre.dataserver.vmName)' from template..."
$params = @{
    Administrator_Password           = (ConvertTo-SecureString $vmAdminPassword -AsPlainText -Force)
    Administrator_User               = $vmAdminUsername
    BootDiagnostics_Account_Name     = $config.sre.storage.bootdiagnostics.accountName
    Domain_Join_Password             = (ConvertTo-SecureString $domainJoinPassword -AsPlainText -Force)
    Domain_Join_Username             = $config.shm.users.computerManagers.dataServers.samAccountName
    Data_Server_Disk_Egress_Size_GB  = [int]$config.sre.dataserver.disks.egress.sizeGb
    Data_Server_Disk_Egress_Type     = $config.sre.dataserver.disks.egress.type
    Data_Server_Disk_Ingress_Size_GB = [int]$config.sre.dataserver.disks.ingress.sizeGb
    Data_Server_Disk_Ingress_Type    = $config.sre.dataserver.disks.ingress.type
    Data_Server_Disk_Shared_Size_GB  = [int]$config.sre.dataserver.disks.shared.sizeGb
    Data_Server_Disk_Shared_Type     = $config.sre.dataserver.disks.shared.type
    Data_Server_Name                 = $config.sre.dataserver.vmName
    Data_Server_VM_Size              = $config.sre.dataserver.vmSize
    Domain_Name                      = $config.shm.domain.fqdn
    IP_Address                       = $config.sre.dataserver.ip
    OU_Path                          = $config.shm.domain.ous.dataServers.path
    Virtual_Network_Name             = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group   = $config.sre.network.vnet.rg
    Virtual_Network_Subnet           = $config.sre.network.vnet.subnets.data.name
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-data-server-template.json") -Params $params -ResourceGroupName $config.sre.dataserver.rg


# Set locale, install updates and reboot
# --------------------------------------
Add-LogMessage -Level Info "Updating data server VM..."
Invoke-WindowsConfigureAndUpdate -VMName $config.sre.dataserver.vmName -ResourceGroupName $config.sre.dataserver.rg -TimeZone $config.sre.time.timezone.windows -NtpServer $config.shm.time.ntp.serverFqdn


# Configure data server
# ---------------------
Add-LogMessage -Level Info "Configuring data server VM..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dataserver" "scripts" "Configure_Data_Server_Remote.ps1"
$params = @{
    sreNetbiosName       = "`"$($config.sre.domain.netbiosName)`""
    shmNetbiosName       = "`"$($config.shm.domain.netbiosName)`""
    dataMountUser        = "`"$($config.sre.users.serviceAccounts.datamount.samAccountName)`""
    researcherUserSgName = "`"$($config.sre.domain.securityGroups.researchUsers.name)`""
    serverAdminSgName    = "`"$($config.shm.domain.securityGroups.serverAdmins.name)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dataserver.vmName -ResourceGroupName $config.sre.dataserver.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext;
