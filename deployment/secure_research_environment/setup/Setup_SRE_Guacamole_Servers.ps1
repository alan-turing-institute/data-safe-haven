param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
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
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName

$vmName = $config.sre.rds.gateway.vmName
$vmSize = $config.sre.rds.gateway.vmSize
$dcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dcAdminPassword
$dcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dcAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$bootDiagnosticsAccount = $config.sre.storage.bootdiagnostics.accountName
$vmNicName = "${vmName}-NIC"
$vmNic = Get-AzResource -Name $vmNicName
$diskType = "Standard_LRS"

# Create RDS resource group if it does not exist
# ----------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.rds.rg -Location $config.sre.location

# Construct the cloud-init yaml file for the target subscription
# --------------------------------------------------------------
Add-LogMessage -Level Info "Constructing cloud-init from template..."
# Load cloud-init template
$cloudInitFilePath = Join-Path $PSScriptRoot ".." "cloud-init" "cloud-init-guacamole.template.yaml"
$cloudInitTemplate = Get-Content $cloudInitFilePath -Raw
$dockerComposeFilePath = Join-Path $PSScriptRoot ".." "remote" "create-guacamole" "templates" "docker-compose.template.yaml"
$envFilePath = Join-Path $PSScriptRoot ".." "remote" "create-guacamole" "templates" "guacamole.template.env"
$envTemplate = Get-Content $envFilePath -Raw
$dbInitFilePath = Join-Path $PSScriptRoot ".." "remote" "create-guacamole" "templates" "dbinit.template.sql"
$dbInitTemplate = Get-Content $dbInitFilePath -Raw

# Set template expansion variables
$AD_DC_NAME_UPPER = $($config.shm.dc.hostname).ToUpper()
$AD_DC_NAME_LOWER = $($AD_DC_NAME_UPPER).ToLower()
$DOMAIN_UPPER = $($config.shm.domain.fqdn).ToUpper()
$DOMAIN_LOWER = $($DOMAIN_UPPER).ToLower()
$LDAP_HOST = $AD_DC_NAME_UPPER.$DOMAIN_LOWER
$LDAP_PORT = 389
$LDAP_USER_BASE_DN = $config.shm.domain.userOuPath
# Set this to something so that we can use seeAlso when configuring connections, to point to existing groups
# Not very well explained in Guacamole docs, but see "Controlling access using group membership" in https://enterprise.glyptodon.com/doc/latest/storing-connection-data-within-ldap-950383.html
$LDAP_GROUP_BASE_DN = ''
$POSTGRES_PASSWORD = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.guacamoleDBPassword
$GUACAMOLE_PASSWORD = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.guacamoleAdminPassword
$LDAP_GROUP = $config.sre.domain.securityGroups.researchUsers.Name
$VM1 = $config.sre.rds.sessionHost1.vmName
# These aren't used yet, not sure if they are applicable for Guacamole
$LDAP_SEARCH_BIND_DN = "CN=" + $config.sre.users.ldap.dsvm.Name + "," + $config.shm.domain.serviceOuPath
$LDAP_USER = $config.sre.users.ldap.dsvm.samAccountName
$LDAP_FILTER = "(&(objectClass=user)(memberOf=CN=" + $config.sre.domain.securityGroups.researchUsers.Name + "," + $config.shm.domain.securityOuPath + "))"

# Templates/files
$ENV = $ExecutionContext.InvokeCommand.ExpandString($envTemplate)
$DBINIT = $ExecutionContext.InvokeCommand.ExpandString($dbInitTemplate)
$DOCKER_COMPOSE = Get-Content $dockerComposeFilePath -Raw
$cloudInitYaml = $ExecutionContext.InvokeCommand.ExpandString($cloudInitTemplate)

# Notes
# -------------
#
# You don't seem to be able to configure the connections this way. 
# There are three main ways I can see to configure the connections.
# 1. In user-mapping.xml, but that only lets you associate a connection with a single user, not to multiple users, and we don't know the users in advance
# 2. In LDAP attributes (https://guacamole.apache.org/doc/gug/ldap-auth.html#ldap-auth-schema), but I can't see any way that you can set these through Azure AD
# 3. In the database. That means we would need a database (as well as LDAP), which is then usually managed through the Guacamole GUI
#
# You also need to associate each connection with a user explicitly.
# The only way I can see that this could be automated, would be to insert the connection directly into the database when starting up, associated with the AD Group that I *think* all users are members of already.

# Deploy the VM
# -------------
$params = @{
    Name = $vmName
    Size = $vmSize
    AdminPassword = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
    AdminUsername = $dcAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml = $cloudInitYaml
    location = $config.sre.location
    NicId = $vmNic.Id
    OsDiskType = $diskType
    ResourceGroupName = $config.sre.rds.rg
}
$_ = Deploy-UbuntuVirtualMachine @params

# Poll VM to see whether it has finished running
Add-LogMessage -Level Info "Waiting for cloud-init provisioning to finish (this will take 5+ minutes)..."
$statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg -Status).Statuses.Code
$progress = 0
while (-not ($statuses.Contains("PowerState/stopped") -and $statuses.Contains("ProvisioningState/succeeded"))) {
    $statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg -Status).Statuses.Code
    $progress += 1
    Write-Progress -Activity "Deployment status" -Status "$($statuses[0]) $($statuses[1])" -PercentComplete $progress
    Start-Sleep 10
}

# Get private IP address for this machine
# ---------------------------------------
$privateIpAddress = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg).Id } | ForEach-Object { $_.IpConfigurations.PrivateIpAddress }
Add-LogMessage -Level Info "Deployment complete at $(Get-Date -UFormat '%d-%b-%Y %R')"
Add-LogMessage -Level Info "This new VM can be accessed with SSH or remote desktop at $privateIpAddress"
