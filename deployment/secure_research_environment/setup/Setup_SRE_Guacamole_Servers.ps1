param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $true, HelpMessage = "Azure Active Directory tenant ID")]
    [string]$tenantId
)

Import-Module Az -ErrorAction Stop
if (-not (Get-Module -Name "Microsoft.Graph.Authentication")) { Import-Module Microsoft.Graph.Authentication -ErrorAction Stop }
if (-not (Get-Module -Name "Microsoft.Graph.Applications")) { Import-Module Microsoft.Graph.Applications -ErrorAction Stop }
Import-Module $PSScriptRoot/../../common/AzureStorage.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Check that we are using the correct provider
# --------------------------------------------
if ($config.sre.remoteDesktop.provider -ne "ApacheGuacamole") {
    Add-LogMessage -Level Fatal "You should not be running this script when using remote desktop provider '$($config.sre.remoteDesktop.provider)'"
}


# Retrieve VNET and subnets
# -------------------------
Add-LogMessage -Level Info "Retrieving virtual network '$($config.sre.network.vnet.name)'..."
$vnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
$guacamoleSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.remoteDesktop.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg
$deploymentSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.deployment.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg


# Get deployment IP address
# -------------------------
$deploymentIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.deployment.cidr -VirtualNetwork $vnet


# Create remote desktop resource group if it does not exist
# ---------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.remoteDesktop.rg -Location $config.sre.location


# Deploy a network card with a public IP address
# ----------------------------------------------
$networkCard = Deploy-VirtualMachineNIC -Name "$($config.sre.remoteDesktop.guacamole.vmName)-NIC" -ResourceGroupName $config.sre.remoteDesktop.rg -Subnet $deploymentSubnet -PrivateIpAddress $deploymentIpAddress -Location $config.sre.location
$publicIp = Deploy-PublicIpAddress -Name "$($config.sre.remoteDesktop.guacamole.vmName)-PIP" -ResourceGroupName $config.sre.remoteDesktop.rg -AllocationMethod Static -Location $config.sre.location
$null = $networkCard | Set-AzNetworkInterfaceIpConfig -Name $networkCard.ipConfigurations[0].Name -SubnetId $deploymentSubnet.Id -PublicIpAddressId $publicIp.Id | Set-AzNetworkInterface


# Register AzureAD application
# ----------------------------
$azureAdApplicationName = "Guacamole SRE $($config.sre.id)"
Add-LogMessage -Level Info "Ensuring that '$azureAdApplicationName' is registered with Azure Active Directory..."
if (Get-MgContext) {
    Add-LogMessage -Level Info "Already authenticated against Microsoft Graph"
} else {
    Connect-MgGraph -TenantId $tenantId -Scopes "Application.ReadWrite.All", "Policy.ReadWrite.ApplicationConfiguration" -ErrorAction Stop
}
try {
    $application = Get-MgApplication -Filter "DisplayName eq '$azureAdApplicationName'"
    if (-not $application) {
        Add-LogMessage -Level Info "Registering '$azureAdApplicationName' with Azure Active Directory..."
        $application = New-MgApplication -DisplayName "$azureAdApplicationName" -SignInAudience "AzureADMyOrg" -Web @{ RedirectUris = @("https://$($config.sre.domain.fqdn)"); ImplicitGrantSettings = @{ EnableIdTokenIssuance = $true } }
    }
    if (Get-MgApplication -Filter "DisplayName eq '$azureAdApplicationName'") {
        Add-LogMessage -Level Success "'$azureAdApplicationName' is already registered in Azure Active Directory"
    } else {
        Add-LogMessage -Level Fatal "Failed to register '$azureAdApplicationName' in Azure Active Directory!"
    }
} catch {
    Add-LogMessage -Level Fatal "Could not connect to Microsoft Graph!" -Exception $_.Exception
}


# Retrieve passwords from the Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.sre.keyVault.name)'..."
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext
$vmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.remoteDesktop.guacamole.adminPasswordSecretName -DefaultLength 20
$guacamoleDbPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.remoteDesktop.guacamole.databaseAdminPasswordSecretName -DefaultLength 20 -AsPlaintext
$ldapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext


# Construct the cloud-init yaml file
# ----------------------------------
Add-LogMessage -Level Info "Constructing cloud-init from template..."
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init"
$cloudInitTemplate = Join-Path $cloudInitBasePath "cloud-init-guacamole.template.yaml" | Get-Item | Get-Content -Raw
$cloudInitTemplate = Expand-CloudInitResources -Template $cloudInitTemplate -ResourcePath (Join-Path $cloudInitBasePath "resources")
# Expand mustache template variables
$cloudInitYaml = $cloudInitTemplate.Replace("{{application_id}}", $application.AppId).
                                    Replace("{{disable_copy}}", ($config.sre.remoteDesktop.networkRules.copyAllowed ? 'false' : 'true')).
                                    Replace("{{disable_paste}}", ($config.sre.remoteDesktop.networkRules.pasteAllowed ? 'false' : 'true')).
                                    Replace("{{initial_compute_vm_ip}}", (Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.compute.cidr -Offset 160)).
                                    Replace("{{initial_compute_vm_ip}}", (Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.compute.cidr -Offset 160)).
                                    Replace("{{ldap-group-base-dn}}", $config.shm.domain.securityOuPath).
                                    Replace("{{ldap-group-filter}}", "(&(objectClass=group)(CN=SG $($config.sre.domain.netbiosName)*))").
                                    Replace("{{ldap-group-researchers}}", $config.sre.domain.securityGroups.researchUsers.name).
                                    Replace("{{ldap-group-system-administrators}}", $config.sre.domain.securityGroups.systemAdministrators.name).
                                    Replace("{{ldap-groups-base-dn}}", $config.shm.domain.ous.securityGroups.path).
                                    Replace("{{ldap-hostname}}", "$(($config.shm.dc.hostname).ToUpper()).$(($config.shm.domain.fqdn).ToLower())").
                                    Replace("{{ldap-port}}", 389).
                                    Replace("{{ldap-search-user-dn}}", "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)").
                                    Replace("{{ldap-search-user-password}}", $ldapSearchPassword).
                                    Replace("{{ldap-user-base-dn}}", $config.shm.domain.ous.researchUsers.path).
                                    Replace("{{ldap-user-filter}}", "(&(objectClass=user)(|(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path))(memberOf=CN=$($config.shm.domain.securityGroups.serverAdmins.name),$($config.shm.domain.ous.securityGroups.path))))").
                                    Replace("{{ntp-server-0}}", ($config.shm.time.ntp.serverAddresses)[0]).
                                    Replace("{{ntp-server-1}}", ($config.shm.time.ntp.serverAddresses)[1]).
                                    Replace("{{ntp-server-2}}", ($config.shm.time.ntp.serverAddresses)[2]).
                                    Replace("{{ntp-server-3}}", ($config.shm.time.ntp.serverAddresses)[3]).
                                    Replace("{{postgres-password}}", $guacamoleDbPassword).
                                    Replace("{{public_ip_address}}", $publicIp.IpAddress).
                                    Replace("{{shm_dc_ip_address}}", $config.shm.dc.ip).
                                    Replace("{{sre_fqdn}}", $config.sre.domain.fqdn).
                                    Replace("{{ssl_ciphers}}", ((Get-SslCipherSuites)["openssl"] | Join-String -Separator ":")).
                                    Replace("{{tenant_id}}", $tenantId).
                                    Replace("{{timezone}}", $config.sre.time.timezone.linux)


# Deploy the VM
# -------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$params = @{
    AdminPassword          = $vmAdminPassword
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitYaml
    ImageSku               = "20.04-LTS"
    Location               = $config.sre.location
    Name                   = $config.sre.remoteDesktop.guacamole.vmName
    NicId                  = $networkCard.Id
    OsDiskSizeGb           = $config.sre.remoteDesktop.guacamole.disks.os.sizeGb
    OsDiskType             = $config.sre.remoteDesktop.guacamole.disks.os.type
    ResourceGroupName      = $config.sre.remoteDesktop.rg
    Size                   = $config.sre.remoteDesktop.guacamole.vmSize
}
$null = Deploy-UbuntuVirtualMachine @params


# Change subnets and IP address while the VM is off then restart
# --------------------------------------------------------------
Update-VMIpAddress -Name $config.sre.remoteDesktop.guacamole.vmName -ResourceGroupName $config.sre.remoteDesktop.rg -Subnet $guacamoleSubnet -IpAddress $config.sre.remoteDesktop.guacamole.ip
Start-VM -Name $config.sre.remoteDesktop.guacamole.vmName -ResourceGroupName $config.sre.remoteDesktop.rg


# Add DNS records for Guacamole server
# ------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.dns.subscriptionName -ErrorAction Stop
$dnsTtlSeconds = 30
# Set the A record for the SRE FQDN
Add-LogMessage -Level Info "[ ] Setting 'A' record for $($config.sre.domain.fqdn) to $($publicIp.IpAddress)"
Remove-AzDnsRecordSet -Name "@" -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
$null = New-AzDnsRecordSet -Name "@" -RecordType A -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Ipv4Address $publicIp.IpAddress)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'A' record for $($config.sre.domain.fqdn)"
} else {
    Add-LogMessage -Level Fatal "Failed to set 'A' record for $($config.sre.domain.fqdn)!"
}
# Set the CAA record for the SRE FQDN
Add-LogMessage -Level Info "[ ] Setting CAA record for $($config.sre.domain.fqdn) to state that certificates will be provided by Let's Encrypt"
Remove-AzDnsRecordSet -Name "@" -RecordType CAA -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
$null = New-AzDnsRecordSet -Name "@" -RecordType CAA -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -CaaFlags 0 -CaaTag "issue" -CaaValue "letsencrypt.org")
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'CAA' record for $($config.sre.domain.fqdn)"
} else {
    Add-LogMessage -Level Fatal "Failed to set 'CAA' record for $($config.sre.domain.fqdn)!"
}
# Set the CNAME record for the remote desktop server
$serverHostname = "$($config.sre.remoteDesktop.guacamole.hostname)".ToLower()
Add-LogMessage -Level Info "[ ] Setting CNAME record for $serverHostname to point to the 'A' record in $($config.sre.domain.fqdn)"
Remove-AzDnsRecordSet -Name $serverHostname -RecordType CNAME -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg
$null = New-AzDnsRecordSet -Name $serverHostname -RecordType CNAME -ZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -Ttl $dnsTtlSeconds -DnsRecords (New-AzDnsRecordConfig -Cname $config.sre.domain.fqdn)
if ($?) {
    Add-LogMessage -Level Success "Successfully set 'CNAME' record for $serverHostname"
} else {
    Add-LogMessage -Level Fatal "Failed to set 'CNAME' record for $serverHostname!"
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
