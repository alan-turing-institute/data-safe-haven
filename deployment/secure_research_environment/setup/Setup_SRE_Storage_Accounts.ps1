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
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force

# Get config and set context
# ------------------
$config = Get-SreConfig $sreId


$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName



# Ensure that storage account exists (throw exception if there's a problem)
Add-LogMessage -Level Info "Ensuring that storage account $($config.shm.storage.datastorage.accountName) exists"
$storageAccount = Get-AzStorageAccount -ResourceGroupName $config.shm.storage.datastorage.rg -Name $config.shm.storage.datastorage.accountName -ErrorAction silentlycontinue
if ($storageAccount) {
    Add-LogMessage -Level InfoSuccess "Found storage account $($config.shm.storage.datastorage.accountName)"
} else {
    try {
        $storageAccount = New-AzStorageAccount -ResourceGroupName $config.shm.storage.datastorage.rg -Name $config.shm.storage.datastorage.accountName -Location $config.shm.location -SkuName Standard_RAGRS -Kind StorageV2 -ErrorAction Stop
        Add-LogMessage -Level Success "Created storage account $($config.shm.storage.datastorage.accountName)"
    } catch {
        Add-LogMessage -Level Fatal "Failed to create storage account '$($config.shm.storage.datastorage.accountName)'!"
    }
}


# Ensure that container exists in storage account (throw exception if there's a problem)
$containerName = "ingress"
Add-LogMessage -Level Info "Ensuring that storage container $($containerName) exists"
Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $config.shm.storage.datastorage.rg -Name $config.shm.storage.datastorage.accountName -DefaultAction allow

$storageContainer = Get-AzStorageContainer -Context $storageAccount.Context -Name $containerName -ClientTimeoutPerRequest 300 -ErrorAction silentlycontinue

if ($storageContainer) {
    Add-LogMessage -Level InfoSuccess "Found container '$containerName' in storage account '$($config.shm.storage.datastorage.accountName)'"
} else {
    try {
        $storageContainer = New-AzStorageContainer -Name $containerName -Context $storageAccount.Context -ErrorAction Stop
        Add-LogMessage -Level Success "Created container '$containerName' in storage account '$($config.shm.storage.datastorage.accountName)'"
    } catch {
        Add-LogMessage -Level Fatal "Failed to create container '$containerName' in storage account '$($config.shm.storage.datastorage.accountName)'!"
    }
}
Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $config.shm.storage.datastorage.rg -Name $config.shm.storage.datastorage.accountName -DefaultAction Deny


# # Check if it is available or not
# $availability = Get-AzStorageAccountNameAvailability -Name $sa.accountName


# if($availability.NameAvailable){

#     # Create storage account if it does not exist
#       # ---------------------------------------------------
#     Add-LogMessage -Level Info "Creating storage account '$($sa.accountName)' under '$($sa.rg)' in the subscription '$($config.shm.subscriptionName)'"

#     $_ = Deploy-ResourceGroup -Name $sa.rg -Location $config.shm.location

#     # Create storage account
#     $storageAccount = New-AzStorageAccount -ResourceGroupName $sa.rg -Name $sa.accountName -Location $config.shm.location  -SkuName Standard_RAGRS -Kind StorageV2

#     # Deny network access
#     Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $sa.rg -Name $sa.accountName -DefaultAction Deny

#     # Create a blob container: ingress, which will have associated a read only SAS token
#     New-AzStorageContainer -Name "ingress" -Context $storageAccount.Context

#     Add-LogMessage -Level Info "The storage account '$($sa.accountName)' has been created in the subscription '$($config.shm.subscriptionName)'"
#     }

# else {
#     Add-LogMessage -Level Info "The storage account '$($sa.accountName)' already exists, try a different name"
#     exit
# }

# Get the storage account object
$sa = $config.shm.storage.datastorage

# Create the ingress SAS token and store it in a secret

# $accountKeys = Get-AzStorageAccountKey -ResourceGroupName $config.shm.storage.datastorage.rg -Name $storageAccount.context.name

# $storageContext = New-AzStorageContext -StorageAccountName $storageAccount.context.name -StorageAccountKey $accountKeys[0].Value

# Hardcoded 1 year for the moment
#$ingressSAS = New-AzStorageContainerSASToken -Name "ingress" -Context $storageContext -Permission "rlw" -StartTime 0 -ExpiryTime 365

$ingressSAS = New-AccountSasToken -subscriptionName "$($config.shm.subscriptionName)" `
                               -resourceGroup "$($config.shm.storage.datastorage.rg)" `
                               -AccountName "$($config.shm.storage.datastorage.accountName)" `
                               -Service "Blob" `
                               -ResourceType "Container" `
                               -Permission "rlw"
                               -validityHours "8760"

# Create the private endpoint
# ---------------------------
$resource = Get-AzResource -Name $sa.accountName -ExpandProperties
Write-Host "$($resource.ResourceId)"
Write-Host "$($storageAccount.Id)"
$privateEndpointName = $sa.accountName + "-endpoint"

$privateDnsZoneName = $($sa.accountName +"." + "blob.core.windows.net").ToLower()

$privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$($privateEndpointName)ServiceConnection" `
-PrivateLinkServiceId $resource.ResourceId `
-GroupId $sa.GroupId


# Switching back to the SRE subscription for storing SAS in the secret vault
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Ensure the keyvault exists and set its access policies
# ------------------------------------------------------
Add-LogMessage -Level Info "Ensuring that secrets exist in key vault '$($config.sre.keyVault.name)'..."

$_ = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.storageIngressSAS -DefaultValue "$ingressSAS"

if ($?) {
    Add-LogMessage -Level Success "Uploading the ingressSAS succeeded"
    }
 else {
    Add-LogMessage -Level Fatal "Uploading the ingressSAS failed!"
    }


$virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name

$subnet = $virtualNetwork `
| Select -ExpandProperty subnets `
| Where-Object  {$_.Name -eq $config.sre.network.subnets.data.name}

$privateEndpoint = Get-AzPrivateEndpoint -name $privateEndpointName

if (-not $privateEndpoint){
    Add-LogMessage -Level Info "Creating private endpoint '$($privateEndpointName)' to resource '$($sa.accountName)'"
    $privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $config.sre.network.vnet.rg `
    -Name $privateEndpointName `
    -Location $config.sre.Location `
    -Subnet $subnet `
    -PrivateLinkServiceConnection $privateEndpointConnection}
    $privateip = (Get-AzNetworkInterface -Resourceid $($privateEndpoint.NetworkInterfaces.id)).IpConfigurations[0].PrivateIpAddress


Add-LogMessage -Level Info "Setting up DNS Zone"

$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName

$params = @{
    ZoneName = $privateDnsZoneName
    ipaddress = $privateip
    update  =  ($dnsForceUpdate ? "force" : "non forced")

}

$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_storage" "set_dns_zone.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -vmName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
