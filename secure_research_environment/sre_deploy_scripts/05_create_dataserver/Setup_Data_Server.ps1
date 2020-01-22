param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force


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


# Deploy data server from template
# --------------------------------
Add-LogMessage -Level Info "Creating data server '$($config.sre.dataserver.vmName)' from template..."
$params = @{
    "SRE ID" = $config.sre.id
    "Data Server Name" = $config.sre.dataserver.vmName
    "Domain Name" = $config.sre.domain.fqdn
    "VM Size" = $config.sre.dataserver.vmSize
    "IP Address" = $config.sre.dataserver.ip
    "Administrator User" = $dcAdminUsername
    "Administrator Password" = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
    "Virtual Network Name" = $config.sre.network.vnet.name
    "Virtual Network Resource Group" = $config.sre.network.vnet.rg
    "Virtual Network Subnet" = $config.sre.network.subnets.data.name
}
Deploy-ArmTemplate -TemplatePath "$PSScriptRoot/sre-data-server-template.json" -Params $params -ResourceGroupName $config.sre.dataserver.rg


# Move Data Server VM into correct OU
# -----------------------------------
Add-LogMessage -Level Info "Moving Data Server VM into correct OU on SRE DC..."
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$scriptPath = Join-Path "remote_scripts" "Move_Data_Server_VM_Into_OU.ps1"
$params = @{
    sreDn = "`"$($config.sre.domain.dn)`""
    sreNetbiosName = "`"$($config.sre.domain.netbiosName)`""
    dataServerHostname = "`"$($config.sre.dataserver.hostname)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dc.vmName -ResourceGroupName $config.sre.dc.rg
Write-Output $result.Value


# Configure Data Server VM
# ------------------------
Add-LogMessage -Level Info "Configuring data server VM..."
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
# $scriptPath = Join-Path "remote_scripts" "Configure_Data_Server_Remote.ps1"
$templateScript = Get-Content -Path (Join-Path $PSScriptRoot "remote_scripts" "Configure_Data_Server_Remote.ps1") -Raw
$configurationScript = Get-Content -Path (Join-Path $PSScriptRoot ".." ".." ".." "common_powershell" "remote" "Configure_Windows.ps1") -Raw
$setLocaleDnsAndUpdate = $templateScript.Replace("# LOCALE CODE IS PROGRAMATICALLY INSERTED HERE", $configurationScript)
$params = @{
    sreNetbiosName = "`"$($config.sre.domain.netbiosName)`""
    shmNetbiosName = "`"$($config.shm.domain.netbiosName)`""
    researcherUserSgName = "`"$($config.sre.domain.securityGroups.researchUsers.name)`""
    serverAdminSgName = "`"$($config.sre.domain.securityGroups.serverAdmins.name)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -Script $setLocaleDnsAndUpdate -VMName $config.sre.dataserver.vmName -ResourceGroupName $config.sre.dataserver.rg
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;
