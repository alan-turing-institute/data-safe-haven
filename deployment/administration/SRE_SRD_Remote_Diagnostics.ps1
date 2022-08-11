param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter last octet of SRD IP address (e.g. 160)")]
    [string]$ipLastOctet
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/RemoteCommands -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Find VM with private IP address matching the provided last octet
# ----------------------------------------------------------------
Add-LogMessage -Level Info "Finding SRD with last IP octet: $ipLastOctet"
$vmId = Get-AzNetworkInterface -ResourceGroupName $config.sre.srd.rg | Where-Object { ($_.IpConfigurations.PrivateIpAddress).Split(".") -eq $ipLastOctet } | ForEach-Object { $_.VirtualMachine.Id }
$vmIpAddress = (Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $vmId }).IpConfigurations.PrivateIpAddress
$vm = Get-AzVM -ResourceGroupName $config.sre.srd.rg | Where-Object { $_.Id -eq $vmId }
if ($?) {
    Add-LogMessage -Level Success "Found SRD '$($vm.Name)'"
} else {
    Add-LogMessage -Level Fatal "Could not find VM with last IP octet '$ipLastOctet'"
}


# Run remote diagnostic scripts
# -----------------------------
Invoke-Expression -Command "$(Join-Path $PSScriptRoot '..' 'secure_research_environment' 'setup' 'Run_SRE_SRD_Remote_Diagnostics.ps1') -shmId $shmId -sreId $sreId -ipLastOctet $ipLastOctet"


# Get LDAP secret from the Key Vault
# ----------------------------------
Add-LogMessage -Level Info "[ ] Loading LDAP secret from Key Vault '$($config.sre.keyVault.name)'"
$ldapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext
if ($ldapSearchPassword) {
    Add-LogMessage -Level Success "Found LDAP secret in the Key Vault"
} else {
    Add-LogMessage -Level Fatal "Could not load LDAP secret from Key Vault '$($config.sre.keyVault.name)'"
}


# Update LDAP secret on the SRD
# -----------------------------
Update-VMLdapSecret -Name $vm.Name -ResourceGroupName $config.sre.srd.rg -LdapSearchPassword $ldapSearchPassword


# Update LDAP secret in local Active Directory on the SHM DC
# ----------------------------------------------------------
Update-AdLdapSecret -Name $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -SubscriptionName $config.shm.subscriptionName -LdapSearchPassword $ldapSearchPassword -LdapSearchSamAccountName $config.sre.users.serviceAccounts.ldapSearch.samAccountName


# Update DNS record on the SHM for this VM
# ----------------------------------------
Update-VMDnsRecords -DcName $config.shm.dc.vmName -DcResourceGroupName $config.shm.dc.rg -BaseFqdn $config.shm.domain.fqdn -ShmSubscriptionName $config.shm.subscriptionName -VmHostname $vm.Name -VmIpAddress $vmIpAddress


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
