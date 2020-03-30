param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
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
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName

$vmName = $config.sre.guacamole.vmName
$vmSize = $config.sre.guacamole.vmSize
$dcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dcAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$dcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dcAdminPassword
# $bootDiagnosticsAccount = $config.sre.storage.bootdiagnostics.accountName
# $vmNicName = "${vmName}-NIC"
# $vmNic = Get-AzResource -Name $vmNicName


# Create RDS resource group if it does not exist
# ----------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.guacamole.rg -Location $config.sre.location

# Construct the cloud-init yaml file for the target subscription
# --------------------------------------------------------------
Add-LogMessage -Level Info "Constructing cloud-init from template..."

# Load db-init template
$dbInitFilePath = Join-Path $PSScriptRoot ".." "remote" "create_guacamole" "templates" "dbinit.template.sql"
$dbInitTemplate = Get-Content $dbInitFilePath -Raw

# Set template expansion variables
$GUACAMOLE_PASSWORD = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.guacamoleAdminPassword
$RESEARCHERS_LDAP_GROUP = $config.sre.domain.securityGroups.researchUsers.Name
$SESSION_HOST_1 = $config.sre.rds.sessionHost1.hostname
$SESSION_HOST_2 = $config.sre.rds.sessionHost2.hostname

$DBINIT = $ExecutionContext.InvokeCommand.ExpandString($dbInitTemplate)

# Load cloud-init template
$cloudInitFilePath = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-guacamole.template.yaml"
$cloudInitTemplate = Get-Content $cloudInitFilePath -Raw

# Set template expansion variables
# The LDAP_* variables are passed through to the guacamole Docker container
# They are not documented, but see https://github.com/apache/guacamole-client/blob/1.1.0/guacamole-docker/bin/start.sh (in `associate_ldap`) for a list of valid keys
# They map to the properties listed in https://guacamole.apache.org/doc/gug/ldap-auth.html#guac-ldap-config
$LDAP_HOSTNAME = "$(($config.shm.dc.hostname).ToUpper()).$(($config.shm.domain.fqdn).ToLower())"
$LDAP_PORT = 389 # or 636 for LDAP over SSL?
$LDAP_USER_BASE_DN = $config.shm.domain.userOuPath
# Set this so that connection information can be picked up from group membership.
# Not very well explained in Guacamole docs, but see "Controlling access using group membership" in https://enterprise.glyptodon.com/doc/latest/storing-connection-data-within-ldap-950383.html
$LDAP_GROUP_BASE_DN = $config.shm.domain.securityOuPath
$POSTGRES_PASSWORD = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.guacamoleDBPassword

# Templates/files
$cloudInitYaml = $ExecutionContext.InvokeCommand.ExpandString($cloudInitTemplate)

# Check that VNET and subnet exist
# --------------------------------
Add-LogMessage -Level Info "Looking for virtual network '$($config.sre.network.vnet.name)'..."
# $vnet = $null
try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.Name -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException]{
    Add-LogMessage -Level Fatal "Virtual network '$($config.sre.network.vnet.name)' could not be found!"
}
Add-LogMessage -Level Success "Found virtual network '$($vnet.Name)' in $($vnet.ResourceGroupName)"
$subnetName = $config.sre.network.subnets.rds.name
Add-LogMessage -Level Info "Looking for subnet network '$subnetName'..."
$subnet = $vnet.subnets | Where-Object { $_.Name -eq $subnetName }
if ($null -eq $subnet) {
    Add-LogMessage -Level Fatal "Subnet '$subnetName' could not be found in virtual network '$($vnet.Name)'!"
}
Add-LogMessage -Level Success "Found subnet '$($subnet.Name)' in $($vnet.Name)"


# Common settings
# ---------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$diskType = "Standard_LRS"


# Deploy a NIC with a public IP address
# -------------------------------------
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.guacamole.rg -Subnet $subnet -PrivateIpAddress $config.sre.guacamole.ip -Location $config.sre.location
$publicIP = New-AzPublicIpAddress -Name "$vmName-PIP" -ResourceGroupName $config.sre.guacamole.rg -AllocationMethod Static -IdleTimeoutInMinutes 4 -Location $config.sre.location
$_ = $vmNic | Set-AzNetworkInterfaceIpConfig -Name $vmNic.ipConfigurations[0].Name -SubnetId $subnet.Id -PublicIpAddressId $publicIP.Id | Set-AzNetworkInterface


# Deploy the VM
# -------------
$params = @{
    Name = $vmName
    Size = $vmSize
    AdminPassword = $dcAdminPassword
    AdminUsername = $dcAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml = $cloudInitYaml
    location = $config.sre.location
    NicId = $vmNic.Id
    OsDiskType = $diskType
    ResourceGroupName = $config.sre.guacamole.rg
}
$_ = Deploy-UbuntuVirtualMachine @params

# Poll VM to see whether it has finished running
Add-LogMessage -Level Info "Waiting for cloud-init provisioning to finish (this will take 5+ minutes)..."
$statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.guacamole.rg -Status).Statuses.Code
$progress = 0
while (-not ($statuses.Contains("PowerState/stopped") -and $statuses.Contains("ProvisioningState/succeeded"))) {
    $statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.guacamole.rg -Status).Statuses.Code
    $progress = [math]::min(100, $progress + 1)
    Write-Progress -Activity "Deployment status" -Status "$($statuses[0]) $($statuses[1])" -PercentComplete $progress
    Start-Sleep 10
}

# # VM must be off for us to switch NSG
# # -----------------------------------
# Add-LogMessage -Level Info "Switching to secure NSG '$($secureNsg.Name)'..."
# Add-VmToNSG -VMName $vmName -NSGName $secureNsg.Name


# Restart after the NSG switch
# ----------------------------
Add-LogMessage -Level Info "Rebooting $vmName..."
Enable-AzVM -Name $vmName -ResourceGroupName $config.sre.guacamole.rg
if ($?) {
    Add-LogMessage -Level Success "Rebooting '${vmName}' succeeded"
} else {
    Add-LogMessage -Level Fatal "Rebooting '${vmName}' failed!"
}
