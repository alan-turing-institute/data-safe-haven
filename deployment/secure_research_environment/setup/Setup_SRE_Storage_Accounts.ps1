# Setup script that creates a storage account and related private endpoint if in the same subscription
# or only the private endpoint to already existing resources in other subscriptions.

param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId,
  [Parameter(Position=1, Mandatory = $false, HelpMessage = "Used to force the update of DNS record")]
  [switch]$dnsForceUpdate
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force

# Get config and set context
# ------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName


# Ensure that storage account exists
# ----------------------------------
Add-LogMessage -Level Info "Ensuring that storage account $($config.shm.storage.datastorage.accountName) exists"
$storageAccount = Get-AzStorageAccount -ResourceGroupName $config.shm.storage.datastorage.rg -Name $config.shm.storage.datastorage.accountName -ErrorAction SilentlyContinue
if ($storageAccount) {
    Add-LogMessage -Level InfoSuccess "Found storage account $($config.shm.storage.datastorage.accountName)"
} else {
    try {
        $storageAccount = New-AzStorageAccount -ResourceGroupName $config.shm.storage.datastorage.rg -Name $config.shm.storage.datastorage.accountName -Location $config.shm.location -SkuName Standard_RAGRS -Kind StorageV2 -ErrorAction Stop
        Add-LogMessage -Level Success "Created storage account $($config.shm.storage.datastorage.accountName)"
    } catch [System.ArgumentException] {
        Add-LogMessage -Level Fatal "Failed to create storage account '$($config.shm.storage.datastorage.accountName)'!"
    }
}


# Ensure that container exists in storage account
# -----------------------------------------------
foreach ($containerName in @("ingress")) {
    Add-LogMessage -Level Info "Ensuring that storage container $($containerName) exists"
    $null = Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $config.shm.storage.datastorage.rg -Name $config.shm.storage.datastorage.accountName -DefaultAction Allow
    Start-Sleep 30  # wait for the permission change to propagate
    $storageContainer = Get-AzStorageContainer -Name $containerName -Context $storageAccount.Context -ClientTimeoutPerRequest 300 -ErrorAction SilentlyContinue
    if ($storageContainer) {
        Add-LogMessage -Level InfoSuccess "Found container '$containerName' in storage account '$($config.shm.storage.datastorage.accountName)'"
    } else {
        try {
            $storageContainer = New-AzStorageContainer -Name $containerName -Context $storageAccount.Context -ErrorAction Stop
            Add-LogMessage -Level Success "Created container '$containerName' in storage account '$($config.shm.storage.datastorage.accountName)'"
        } catch [Microsoft.Azure.Storage.StorageException] {
            Add-LogMessage -Level Fatal "Failed to create container '$containerName' in storage account '$($config.shm.storage.datastorage.accountName)'!"
        }
    }
    $null = Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $config.shm.storage.datastorage.rg -Name $config.shm.storage.datastorage.accountName -DefaultAction Deny
}


# Create a SAS token (hardcoded 1 year for the moment)
# ----------------------------------------------------
$ingressSAS = New-AccountSasToken -SubscriptionName "$($config.shm.subscriptionName)" `
                                  -ResourceGroup "$($config.shm.storage.datastorage.rg)" `
                                  -AccountName "$($config.shm.storage.datastorage.accountName)" `
                                  -Service "$($config.shm.storage.datastorage.GroupId)" `
                                  -ResourceType "Container" `
                                  -Permission "rlw" `
                                  -validityHours "8760"

# Create the private endpoint
# ---------------------------
$privateEndpointName = "$($storageAccount.Context.Name)-endpoint"
$privateDnsZoneName = "$($storageAccount.Context.Name).blob.core.windows.net".ToLower()
$privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$($privateEndpointName)ServiceConnection" -PrivateLinkServiceId $storageAccount.Id -GroupId $config.shm.storage.datastorage.GroupId


# Ensure the keyvault exists and set its access policies
# ------------------------------------------------------
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName
Add-LogMessage -Level Info "Ensuring that secrets exist in key vault '$($config.sre.keyVault.name)'..."
$null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.storageIngressSAS -DefaultValue "$ingressSAS"
if ($?) {
    Add-LogMessage -Level Success "Uploading the ingressSAS succeeded"
} else {
    Add-LogMessage -Level Fatal "Uploading the ingressSAS failed!"
}


# Ensure that private endpoint exists
# -----------------------------------
$privateEndpoint = Get-AzPrivateEndpoint -Name $privateEndpointName -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction SilentlyContinue
if ($privateEndpoint) {
    Add-LogMessage -Level Warning "Removing existing private endpoint '$($privateEndpointName)'"
    Remove-AzPrivateEndpoint -Name $privateEndpointName -ResourceGroupName $config.sre.network.vnet.rg -Force
}
Add-LogMessage -Level Info "Creating private endpoint '$($privateEndpointName)' to resource '$($storageAccount.context.name)'"
$virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name
$subnet = Get-AzSubnet -Name $config.sre.network.subnets.data.name -VirtualNetwork $virtualNetwork
$privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $config.sre.network.vnet.rg `
                                         -Name $privateEndpointName `
                                         -Location $config.sre.Location `
                                         -Subnet $subnet `
                                         -PrivateLinkServiceConnection $privateEndpointConnection
if ($?) {
    Add-LogMessage -Level Success "Successfully created private endpoint '$($privateEndpointName)'"
} else {
    Add-LogMessage -Level Fatal "Failed to create private endpoint '$($privateEndpointName)'!"
}
$privateip = (Get-AzNetworkInterface -Resourceid $($privateEndpoint.NetworkInterfaces.id)).IpConfigurations[0].PrivateIpAddress


# Set up DNS zone
# ---------------
Add-LogMessage -Level Info "Setting up DNS Zone"
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$params = @{
    ZoneName = $privateDnsZoneName
    ipaddress = $privateip
    update  =  ($dnsForceUpdate ? "force" : "non forced")

}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_storage" "set_dns_zone.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -vmName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
