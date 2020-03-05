param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -Subscription $config.sre.subscriptionName


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$dcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminPassword


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
    Administrator_Password = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
    Administrator_User = $dcAdminUsername
    BootDiagnostics_Account_Name = $config.sre.storage.bootdiagnostics.accountName
    Data_Server_Name = $config.sre.dataserver.vmName
    Domain_Name = $config.sre.domain.fqdn
    IP_Address = $config.sre.dataserver.ip
    Virtual_Network_Name = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet = $config.sre.network.subnets.data.name
    VM_Size = $config.sre.dataserver.vmSize
}
Deploy-ArmTemplate -TemplatePath "$PSScriptRoot/sre-data-server-template.json" -Params $params -ResourceGroupName $config.sre.dataserver.rg


# Move Data Server VM into correct OU
# -----------------------------------
Add-LogMessage -Level Info "Adding data server to correct security group..."
$scriptPath = Join-Path "remote_scripts" "Move_Data_Server_VM_Into_OU.ps1"
$params = @{
    sreDn = "`"$($config.sre.domain.dn)`""
    sreNetbiosName = "`"$($config.sre.domain.netbiosName)`""
    dataServerHostname = "`"$($config.sre.dataserver.hostname)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dc.vmName -ResourceGroupName $config.sre.dc.rg -Parameter $params
Write-Output $result.Value




# # Install required Powershell packages
# # ------------------------------------
# Add-LogMessage -Level Info "[ ] Installing required Powershell packages on data server: '$($config.sre.dataserver.vmName)'..."
# $scriptPath = Join-Path $PSScriptRoot ".." ".." ".." "common_powershell" "remote" "Install_Powershell_Modules.ps1"
# $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dataserver.vmName -ResourceGroupName $config.sre.dataserver.rg
# Write-Output $result.Value


# # Set the OS language to en-GB and install updates
# # ------------------------------------------------
# $templateScript = Get-Content -Path (Join-Path $PSScriptRoot "remote_scripts" "Configure_Data_Server_Remote.ps1") -Raw
# $configurationScript = Get-Content -Path (Join-Path $PSScriptRoot ".." ".." ".." "common_powershell" "remote" "Configure_Windows.ps1") -Raw
# $setLocaleDnsAndUpdate = $templateScript.Replace("# LOCALE CODE IS PROGRAMATICALLY INSERTED HERE", $configurationScript)
# $params = @{
#     sreNetbiosName = "`"$($config.sre.domain.netbiosName)`""
#     shmNetbiosName = "`"$($config.shm.domain.netbiosName)`""
#     researcherUserSgName = "`"$($config.sre.domain.securityGroups.researchUsers.name)`""
#     serverAdminSgName = "`"$($config.sre.domain.securityGroups.serverAdmins.name)`""
# }
# $result = Invoke-RemoteScript -Shell "PowerShell" -Script $setLocaleDnsAndUpdate -VMName $config.sre.dataserver.vmName -ResourceGroupName $config.sre.dataserver.rg -Parameter $params
# Write-Output $result.Value


# Set locale, install updates and reboot
# --------------------------------------
Add-LogMessage -Level Info "Updating data server VM..."
Invoke-WindowsConfigureAndUpdate -VMName $config.sre.dataserver.vmName -ResourceGroupName $config.sre.dataserver.rg -CommonPowershellPath (Join-Path $PSScriptRoot ".." ".." ".." "common_powershell")


# Configure data server
# ---------------------
Add-LogMessage -Level Info "Configuring data server VM..."
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_Data_Server_Remote.ps1"
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
