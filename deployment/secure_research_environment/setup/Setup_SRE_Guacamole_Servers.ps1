param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $true, HelpMessage = "Azure Active Directory tenant ID")]
    [string]$tenantId,
    [Parameter(Mandatory = $false, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$duoIntegration,
    [Parameter(Mandatory = $false, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$duoSecret,
    [Parameter(Mandatory = $false, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$duoApiHost
)

Import-Module Az
#Import-Module Microsoft.Graph
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop

WRite-Host $config.sre.guacamole.fqdn


$vmName = $config.sre.guacamole.vmName
$vmSize = $config.sre.guacamole.vmSize
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext
$vmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.guacamole.adminPasswordSecretName -DefaultLength 20

# # Get/set Duo secrets
# $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
# # $duoIntegrationKey = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.Name -SecretName $config.shm.keyVault.secretNames.duoIntegrationKey -DefaultValue $duoIntegration
# # $duoSecretKey = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.Name -SecretName $config.shm.keyVault.secretNames.duoSecretKey -DefaultValue $duoSecret
# # $duoApiHostname = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.Name -SecretName $config.shm.keyVault.secretNames.duoApiHostname -DefaultValue $duoApiHost
# $null = Set-AzContext -SubscriptionId $config.sre.subscriptionName

# Create RDS resource group if it does not exist
# ----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.guacamole.rg -Location $config.sre.location


# # Load db-init template
# $dbInitFilePath = Join-Path $PSScriptRoot ".." "remote" "create_guacamole" "templates" "dbinit.template.sql"
# $dbInitTemplate = Get-Content $dbInitFilePath -Raw

# # Set template expansion variables
# $GUACAMOLE_PASSWORD = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.guacamoleAdminPassword
# $RESEARCHERS_LDAP_GROUP = $config.sre.domain.securityGroups.researchUsers.Name
# $SESSION_HOST_1 = $config.sre.rds.sessionHost1.hostname
# $SESSION_HOST_2 = $config.sre.rds.sessionHost2.hostname

# $DBINIT = $ExecutionContext.InvokeCommand.ExpandString($dbInitTemplate)

# Retrieve VNET and subnet
# ------------------------
Add-LogMessage -Level Info "Retrieving virtual network '$($config.sre.network.vnet.name)'..."
$vnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
$guacamoleSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.guacamole.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg


# Deploy a NIC with a public IP address
# -------------------------------------
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.guacamole.rg -Subnet $guacamoleSubnet -PrivateIpAddress $config.sre.guacamole.ip -Location $config.sre.location
$publicIp = New-AzPublicIpAddress -Name "$vmName-PIP" -ResourceGroupName $config.sre.guacamole.rg -AllocationMethod Static -IdleTimeoutInMinutes 4 -Location $config.sre.location -Force
$null = $vmNic | Set-AzNetworkInterfaceIpConfig -Name $vmNic.ipConfigurations[0].Name -SubnetId $guacamoleSubnet.Id -PublicIpAddressId $publicIp.Id | Set-AzNetworkInterface


# Add DNS records for Guacamole server
# ------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName -ErrorAction Stop
# # Add DNS records to SRE DNS Zone
# Add-LogMessage -Level Info "Adding DNS record for Guacamole server"
# $dnsTtlSeconds = 30
# # Set the A record
# $recordName = "@"
# Add-LogMessage -Level Info "[ ] Setting 'A' record for gateway host to '$rdsGatewayPublicIp' in SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
# Remove-AzDnsRecordSet -Name $recordName -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
# $null = New-AzDnsRecordSet -Name $recordName -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $rdsGatewayPublicIp)
# if ($?) {
#     Add-LogMessage -Level Success "Successfully set 'A' record for gateway host"
# } else {
#     Add-LogMessage -Level Info "Failed to set 'A' record for gateway host!"
# }
# # Set the CNAME record
# $recordName = "$($config.sre.rds.gateway.hostname)".ToLower()
# Add-LogMessage -Level Info "[ ] Setting CNAME record for gateway host to point to the 'A' record in SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
# Remove-AzDnsRecordSet -Name $recordName -RecordType CNAME -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
# $null = New-AzDnsRecordSet -Name $recordName -RecordType CNAME -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $config.sre.domain.fqdn)
# if ($?) {
#     Add-LogMessage -Level Success "Successfully set 'CNAME' record for gateway host"
# } else {
#     Add-LogMessage -Level Info "Failed to set 'CNAME' record for gateway host!"
# }

# Set an A record
$dnsTtlSeconds = 30
Add-LogMessage -Level Info "[ ] Setting 'A' record for gateway host to '$($publicIp.IpAddress)' in SRE $($config.sre.id) DNS zone ($($config.sre.domain.fqdn))"
Remove-AzDnsRecordSet -Name guacamole -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
$null = New-AzDnsRecordSet -Name guacamole -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $publicIp.IpAddress)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'A' record for gateway host"
} else {
    Add-LogMessage -Level Info "Failed to set 'A' record for gateway host!"
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop

exit 1


# Register AzureAD application
# Connect-MgGraph -TenantId 1d93a235-0c16-4f39-adff-a550719bdb49 -Scopes "Application.ReadWrite.All"
Connect-MgGraph -TenantId $tenantId -Scopes "Application.ReadWrite.All"

# $application.Web.RedirectUris = "https://51.11.148.222"
# Update-MgApplication -ApplicationId $application.Id -Web $application.Web

$application = Get-MgApplication -Filter "DisplayName eq 'Guacamole Server'"
if (-not $application) {
    $application = New-MgApplication -DisplayName "Guacamole Server" -SignInAudience "AzureADMyOrg" -Web @{ RedirectUris = @("https://51.11.148.222", "http://guacamole:8080/guacamole/") }
}


# $Body = @{
#     'resource'= $ARMResource
#     'client_id' = $ClientID
#     'grant_type' = 'client_credentials'
#     'client_secret' = $ClientSecret
# }

# $params = @{
# ContentType = 'application/x-www-form-urlencoded'
# Headers = @{'accept'='application/json'}
# Body = $Body
# Method = 'Post'
# URI = $TokenEndpoint
# }

# $token = Invoke-RestMethod @params

# $accesstoken = $token.access_token

# $url = {https://graph.windows.net/{0}/applications/{1}?api-version=1.6} -f $tennantid,$objectid

# $header = @{
# 'Authorization' = 'Bearer ' + $accesstoken
# 'Content-Type' = 'application/json'
# }

# $json = @{
# oauth2AllowIdTokenImplicitFlow = 'false' #or true
# }

# $body = $json | ConvertTo-Json

# Invoke-RestMethod –Uri $url –Headers $header -Body $body –Method PATCH


# $url = "https://graph.windows.net/${tenantId}/applications/$($application.Id)?api-version=1.6"


$certificateName = $config.sre.keyVault.secretNames.letsEncryptCertificate
# if ($dryRun) { $certificateName += "-dryrun" }


# # Check for existing certificate in Key Vault
# # -------------------------------------------
# Add-LogMessage -Level Info "[ ] Checking whether signed certificate '$certificateName' already exists in Key Vault..."
$kvCertificate = Get-AzKeyVaultCertificate -VaultName $config.sre.keyVault.name -Name $certificateName





# Load cloud-init template
$cloudInitTemplate = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-guacamole.template.yaml" | Get-Item | Get-Content -Raw

# Set template expansion variables
# The LDAP_* variables are passed through to the guacamole Docker container
# They are not documented, but see https://github.com/apache/guacamole-client/blob/1.1.0/guacamole-docker/bin/start.sh (in `associate_ldap`) for a list of valid keys
# They map to the properties listed in https://guacamole.apache.org/doc/gug/ldap-auth.html#guac-ldap-config
# $LDAP_HOSTNAME = "$(($config.shm.dc.hostname).ToUpper()).$(($config.shm.domain.fqdn).ToLower())"
# $LDAP_PORT = 389 # or 636 for LDAP over SSL?
# $LDAP_USER_BASE_DN = $config.shm.domain.userOuPath
# Set this so that connection information can be picked up from group membership.
# Not very well explained in Guacamole docs, but see "Controlling access using group membership" in https://enterprise.glyptodon.com/doc/latest/storing-connection-data-within-ldap-950383.html
# $LDAP_GROUP_BASE_DN = $config.shm.domain.securityOuPath
$guacamoleDbPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.guacamole.databaseAdminPasswordSecretName -DefaultLength 20 -AsPlaintext
$ldapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext


# Construct the cloud-init yaml file for the target subscription
# --------------------------------------------------------------
Add-LogMessage -Level Info "Constructing cloud-init from template..."
$cloudInitTemplate = Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-guacamole.template.yaml" | Get-Item | Get-Content -Raw
$cloudInitYaml = $cloudInitTemplate.Replace("{{application_id}}", $application.AppId).
                                    Replace("<ldap-hostname>", "$(($config.shm.dc.hostname).ToUpper()).$(($config.shm.domain.fqdn).ToLower())").
                                    Replace("<ldap-port>", 389).
                                    Replace("<ldap-group-base-dn>", $config.shm.domain.securityOuPath).
                                    Replace("<ldap-search-bind-dn>", "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)").
                                    Replace("<ldap-search-bind-password>", $ldapSearchPassword).
                                    Replace("<ldap-group-researchers>", $config.sre.domain.securityGroups.researchUsers.Name).
                                    Replace("<postgres-password>", $guacamoleDbPassword).
                                    Replace("<duo-api-hostname>", $duoApiHost).
                                    Replace("<duo-integration-key>", $duoIntegrationKey).
                                    Replace("<duo-secret-key>", $duoSecretKey).
                                    Replace("{{guacamole_fqdn}}", $config.sre.guacamole.fqdn).
                                    Replace("{{public_ip_address}}", $publicIp.IpAddress).
                                    Replace("<shm-dc-ip-address>", $config.shm.dc.ip).
                                    Replace("{{tenant_id}}", $tenantId).
                                    Replace("<ldap-user-base-dn>", $config.shm.domain.ous.researchUsers.path).
                                    Replace("<ldap-user-filter>", "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.Name),$($config.shm.domain.securityOuPath)))").
                                    Replace("<ldap-groups-base-dn>", $config.shm.domain.ous.securityGroups.path).
                                    Replace("<ldap-group-filter>", "(&(objectClass=group)(CN=SG $($config.sre.domain.netbiosName)*))")


# # Check that VNET and subnet exist
# # --------------------------------
# Add-LogMessage -Level Info "Looking for virtual network '$($config.sre.network.vnet.name)'..."
# # $vnet = $null
# try {
#     $vnet = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.Name -ErrorAction Stop
# } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException]{
#     Add-LogMessage -Level Fatal "Virtual network '$($config.sre.network.vnet.name)' could not be found!"
# }
# Add-LogMessage -Level Success "Found virtual network '$($vnet.Name)' in $($vnet.ResourceGroupName)"
# $subnetName = $config.sre.network.subnets.rds.name
# Add-LogMessage -Level Info "Looking for subnet network '$subnetName'..."
# $subnet = $vnet.subnets | Where-Object { $_.Name -eq $subnetName }
# if ($null -eq $subnet) {
#     Add-LogMessage -Level Fatal "Subnet '$subnetName' could not be found in virtual network '$($vnet.Name)'!"
# }
# Add-LogMessage -Level Success "Found subnet '$($subnet.Name)' in $($vnet.Name)"



# Common settings
# ---------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$diskType = "Standard_LRS"


# Deploy the VM
# -------------
$params = @{
    AdminPassword = $vmAdminPassword
    AdminUsername = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml = $cloudInitYaml
    ImageSku = "18.04-LTS"
    Location = $config.sre.location
    Name = $vmName
    NicId = $vmNic.Id
    OsDiskType = $diskType
    ResourceGroupName = $config.sre.guacamole.rg
    Size = $vmSize
}
$null = Deploy-UbuntuVirtualMachine @params






# Write-Host "vmAdminPassword '$vmAdminPassword'"

# # Poll VM to see whether it has finished running
# Add-LogMessage -Level Info "Waiting for cloud-init provisioning to finish (this will take 5+ minutes)..."
# $statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.guacamole.rg -Status).Statuses.Code
# $progress = 0
# while (-not ($statuses.Contains("PowerState/stopped") -and $statuses.Contains("ProvisioningState/succeeded"))) {
#     $statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.guacamole.rg -Status).Statuses.Code
#     $progress = [math]::min(100, $progress + 1)
#     Write-Progress -Activity "Deployment status" -Status "$($statuses[0]) $($statuses[1])" -PercentComplete $progress
#     Start-Sleep 10
# }

# # VM must be off for us to switch NSG
# # -----------------------------------
# Add-LogMessage -Level Info "Switching to secure NSG '$($secureNsg.Name)'..."
# Add-VmToNSG -VMName $vmName -NSGName $secureNsg.Name


# # Restart after the NSG switch
# # ----------------------------
# Add-LogMessage -Level Info "Rebooting $vmName..."
# Enable-AzVM -Name $vmName -ResourceGroupName $config.sre.guacamole.rg
# if ($?) {
#     Add-LogMessage -Level Success "Rebooting '${vmName}' succeeded"
# } else {
#     Add-LogMessage -Level Fatal "Rebooting '${vmName}' failed!"
# }


# # Add DNS records to SRE DNS Zone
# $null = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName
# $baseDnsRecordname = "@"
# $gatewayDnsRecordname = "$($config.sre.rds.gateway.hostname)".ToLower()
# $dnsResourceGroup = $config.shm.dns.rg
# $dnsTtlSeconds = 30
# $sreDomain = $config.sre.domain.fqdn

# # Setting the A record
# Add-LogMessage -Level Info "[ ] Setting 'A' record for gateway host to '$rdsGatewayPublicIp' in SRE $($config.sre.id) DNS zone ($sreDomain)"
# Remove-AzDnsRecordSet -Name $baseDnsRecordname -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
# $result = New-AzDnsRecordSet -Name $baseDnsRecordname -RecordType A -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup `
#                              -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -IPv4Address $rdsGatewayPublicIp)
# if ($?) {
#     Add-LogMessage -Level Success "Successfully set 'A' record for gateway host"
# } else {
#     Add-LogMessage -Level Info "Failed to set 'A' record for gateway host!"
# }

# # Setting the CNAME record
# Add-LogMessage -Level Info "[ ] Setting CNAME record for gateway host to point to the 'A' record in SRE $($config.sre.id) DNS zone ($sreDomain)"
# Remove-AzDnsRecordSet -Name $gatewayDnsRecordname -RecordType CNAME -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
# $result = New-AzDnsRecordSet -Name $gatewayDnsRecordname -RecordType CNAME -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup `
#                              -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $sreDomain)
# if ($?) {
#     Add-LogMessage -Level Success "Successfully set 'CNAME' record for gateway host"
# } else {
#     Add-LogMessage -Level Info "Failed to set 'CNAME' record for gateway host!"
# }

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop