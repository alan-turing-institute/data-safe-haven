# Setup script that creates a storage account, ingress container and the related private endpoint, Forward Lookup Zone and specific A Record

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
Add-LogMessage -Level Info "Ensuring that resource group $($config.sre.storage.datastorage.rg) exists"
$resourceGroup = Get-AzResourceGroup -ResourceGroupName $config.sre.storage.datastorage.rg -ErrorAction SilentlyContinue
if ($resourceGroup) {
    Add-LogMessage -Level InfoSuccess "Found resource group $($config.sre.storage.datastorage.rg)"
} else {
    try {
        $resourceGroup = New-AzResourceGroup -Name $config.sre.storage.datastorage.rg -Location $config.shm.location -ErrorAction Stop
        Add-LogMessage -Level Success "Created resource group $($config.sre.storage.datastorage.rg)"
    } catch [System.ArgumentException] {
        Add-LogMessage -Level Fatal "Failed to create resource group '$($config.sre.storage.datastorage.rg)'!"
    }
}

Add-LogMessage -Level Info "Ensuring that storage account $($config.sre.storage.datastorage.accountName) exists"
$storageAccount = Get-AzStorageAccount -ResourceGroupName $config.sre.storage.datastorage.rg -Name $config.sre.storage.datastorage.accountName -ErrorAction SilentlyContinue
if ($storageAccount) {
    Add-LogMessage -Level InfoSuccess "Found storage account $($config.sre.storage.datastorage.accountName)"
} else {
    try {
        $storageAccount = New-AzStorageAccount -ResourceGroupName $config.sre.storage.datastorage.rg -Name $config.sre.storage.datastorage.accountName -Location $config.shm.location -SkuName Standard_RAGRS -Kind StorageV2 -ErrorAction Stop
        Add-LogMessage -Level Success "Created storage account $($config.sre.storage.datastorage.accountName)"
    } catch [System.ArgumentException] {
        Add-LogMessage -Level Fatal "Failed to create storage account '$($config.sre.storage.datastorage.accountName)'!"
    }
}

Write-Host ($storageAccount | out-String)
Write-Host ($($storageAccount).context | out-String)

# Ensure that container exists in storage account
# -----------------------------------------------
$containerName = $config.sre.storage.datastorage.containers.ingress.name

Add-LogMessage -Level Info "Ensuring that storage container $($containerName) exists"
$storageContainer = Get-AzStorageContainer -Name $containerName -Context $($storageAccount.Context) -ClientTimeoutPerRequest 300 -ErrorAction SilentlyContinue
if ($storageContainer) {
    Add-LogMessage -Level InfoSuccess "Found container '$containerName' in storage account '$($config.sre.storage.datastorage.accountName)'"
} else {
    Add-LogMessage -Level InfoSuccess "$storageContainer = New-AzStorageContainer -Name $containerName -Context $($storageAccount.Context) -ErrorAction Stop"
    try {
        $storageContainer = New-AzStorageContainer -Name $containerName -Context $($storageAccount.Context) -ErrorAction Stop
        Add-LogMessage -Level Success "Created container '$containerName' in storage account '$($config.sre.storage.datastorage.accountName)'"
    } catch [Microsoft.Azure.Storage.StorageException] {
        Add-LogMessage -Level Fatal "Failed to create container '$containerName' in storage account '$($config.sre.storage.datastorage.accountName) with context $($storageAccount.Context) '!"
    }
}


# Create a SAS Policy and SAS token (hardcoded 1 year for the moment)
# ----------------------------------------------------
$accessType = $config.sre.accessPolicies.researcher.nameSuffix

$availablePolicies = Get-AzStorageContainerStoredAccessPolicy -Container $containerName -Context $($storageAccount.Context)

foreach ($Policy in @($availablePolicies)) {
    if ($Policy -like "*$accessType") {
        $SASPolicy = $Policy.Policy
    }
}
if (-Not $SASPolicy){
    $SASPolicy = New-AzStorageContainerStoredAccessPolicy -Container $containerName `
                                                            -Policy $((Get-Date -Format "yyyyMMddHHmmss")+$accessType) `
                                                            -Context $($storageAccount.Context) `
                                                            -Permission $($config.sre.accessPolicies.researcher.permissions) `
                                                            -StartTime (Get-Date).DateTime `
                                                            -ExpiryTime (Get-Date).AddYears(1).DateTime
}

$newSAStoken = New-AzStorageContainerSASToken -Name $containerName `
                                                -Policy $SASPolicy `
                                                -Context $($storageAccount.Context)

$null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name `
                                        -SecretName $config.sre.accessPolicies.researcher.sasSecretName `
                                        -DefaultValue $newSAStoken


# Create the private endpoint
# ---------------------------
$privateEndpointName = "$($storageAccount.Context.Name)-endpoint"
$privateDnsZoneName = "$($storageAccount.Context.Name).blob.core.windows.net".ToLower()
$privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$($privateEndpointName)ServiceConnection" -PrivateLinkServiceId $storageAccount.Id -GroupId $config.sre.storage.datastorage.containers.ingress.storageType


# Ensure the keyvault exists and set its access policies
# ------------------------------------------------------

$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName



# Ensure that private endpoint exists
# -----------------------------------
$privateEndpoint = Get-AzPrivateEndpoint -Name $privateEndpointName -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction SilentlyContinue
if ($privateEndpoint) {
    Add-LogMessage -Level Warning "Removing existing private endpoint '$($privateEndpointName)'"
    Remove-AzPrivateEndpoint -Name $privateEndpointName -ResourceGroupName $config.sre.network.vnet.rg -Force
}
Add-LogMessage -Level Info "Creating private endpoint '$($privateEndpointName)' to resource '$($storageAccount.context.name)'"
$virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name
$subnet = Get-AzSubnet -Name $config.sre.network.vnet.subnets.data.name -VirtualNetwork $virtualNetwork
$privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $config.sre.network.vnet.rg `
                                         -Name $privateEndpointName `
                                         -Location $config.sre.location `
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
