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
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$sreAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminPassword
$shmDcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.dcNpsAdminUsername -DefaultValue "shm$($config.shm.id)admin".ToLower()
$shmDcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.keyVault.secretNames.dcNpsAdminPassword


# Create data server resource group if it does not exist
# ------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.dataserver.rg -Location $config.sre.location


# Set up the NSG for the data server
# ----------------------------------
$nsg = Deploy-NetworkSecurityGroup -Name $config.sre.dataserver.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $nsg `
                             -Name "Deny_Internet" `
                             -Description "Deny Outbound Internet Access" `
                             -Priority 4000 `
                             -Direction Outbound -Access Deny -Protocol * `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix Internet -DestinationPortRange *


# Deploy data server from template
# --------------------------------
Add-LogMessage -Level Info "Creating data server '$($config.sre.dataserver.vmName)' from template..."
$params = @{
    Administrator_Password = (ConvertTo-SecureString $sreAdminPassword -AsPlainText -Force)
    Administrator_User = $sreAdminUsername
    BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
    Data_Server_Name = $config.sre.dataserver.vmName
    DC_Administrator_Password = (ConvertTo-SecureString $shmDcAdminPassword -AsPlainText -Force)
    DC_Administrator_User = $shmDcAdminUsername
    Domain_Name = $config.shm.domain.fqdn
    IP_Address = $config.sre.dataserver.ip
    Virtual_Network_Name = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet = $config.sre.network.subnets.data.name
    VM_Size = $config.sre.dataserver.vmSize
}
Deploy-ArmTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "arm_templates" "sre-data-server-template.json") -Params $params -ResourceGroupName $config.sre.dataserver.rg


# Move Data Server VM into correct OU
# -----------------------------------
$_ = Set-AzContext -Subscription $config.shm.subscriptionName
Add-LogMessage -Level Info "Adding data server to correct security group..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dataserver" "scripts" "Move_Data_Server_VM_Into_OU.ps1"
$params = @{
    shmDn = "`"$($config.shm.domain.dn)`""
    dataServerHostname = "`"$($config.sre.dataserver.hostname)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value
$_ = Set-AzContext -Subscription $config.sre.subscriptionName


# Set locale, install updates and reboot
# --------------------------------------
Add-LogMessage -Level Info "Updating data server VM..."
Invoke-WindowsConfigureAndUpdate -VMName $config.sre.dataserver.vmName -ResourceGroupName $config.sre.dataserver.rg -CommonPowershellPath (Join-Path $PSScriptRoot ".." ".." "common")


# Configure data server
# ---------------------
Add-LogMessage -Level Info "Configuring data server VM..."
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_dataserver" "scripts" "Configure_Data_Server_Remote.ps1"
$params = @{
    sreNetbiosName = "`"$($config.sre.domain.netbiosName)`""
    shmNetbiosName = "`"$($config.shm.domain.netbiosName)`""
    researcherUserSgName = "`"$($config.sre.domain.securityGroups.researchUsers.name)`""
    serverAdminSgName = "`"$($config.sre.domain.securityGroups.serverAdmins.name)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dataserver.vmName -ResourceGroupName $config.sre.dataserver.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
