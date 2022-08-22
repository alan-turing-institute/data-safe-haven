param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az.Accounts
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Create resource group if it does not exist
# ------------------------------------------
$null = Deploy-ResourceGroup -Name $config.monitoring.rg -Location $config.location


# Deploy the Linux update server
# ------------------------------
$cloudInitYaml = Expand-MustacheTemplate -TemplatePath (Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-update-server-linux.mustache.yaml") -Parameters $config
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.storage.bootdiagnostics.accountName -ResourceGroupName $config.storage.bootdiagnostics.rg -Location $config.location
$vmName = $config.monitoring.updateServers.linux.vmName
$params = @{
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.monitoring.updateServers.linux.adminPasswordSecretName -DefaultLength 20)
    AdminUsername          = (Resolve-KeyVaultSecret -VaultName $config.keyVault.name -SecretName $config.keyVault.secretNames.vmAdminUsername -DefaultValue "shm$($config.id)admin".ToLower() -AsPlaintext)
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitYaml
    ImageSku               = "Ubuntu-latest"
    Location               = $config.location
    Name                   = $vmName
    OsDiskSizeGb           = $config.monitoring.updateServers.linux.disks.os.sizeGb
    OsDiskType             = $config.monitoring.updateServers.linux.disks.os.type
    PrivateIpAddress       = $config.monitoring.updateServers.linux.ip
    ResourceGroupName      = $config.monitoring.rg
    Size                   = $config.monitoring.updateServers.linux.vmSize
    Subnet                 = (Get-Subnet -Name $config.network.vnet.subnets.updateServers.name -ResourceGroupName $config.network.vnet.rg -VirtualNetworkName $config.network.vnet.name)
}
Deploy-LinuxVirtualMachine @params | Start-VM


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
