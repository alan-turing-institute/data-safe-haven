param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId,
    [Parameter(Position = 1, Mandatory = $false, HelpMessage = "Used to force the update of DNS record")]
    [switch]$dnsForceUpdate
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName


# Ensure that a container exists in the correct SHM storage account for this SRE
# ------------------------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.datastorage.rg -Location $config.shm.location
$storageAccount = Deploy-StorageAccount -Name $config.sre.storage.datastorage.accountName -ResourceGroupName $config.sre.storage.datastorage.rg -Location $config.shm.location -SkuName "Standard_RAGRS"
$containerName = $config.sre.storage.datastorage.containers.ingress.name
$null = Deploy-StorageContainer -Name $containerName -StorageAccount $storageAccount


# Create a new SAS token (and policy if required)
# -----------------------------------------------
$sasPolicy = Deploy-SasAccessPolicy -Name $config.sre.accessPolicies.researcher.nameSuffix `
                                    -Permission $config.sre.accessPolicies.researcher.permissions `
                                    -StorageAccount $storageAccount `
                                    -ContainerName $containerName `
                                    -ValidityYears 1
$newSAStoken = New-AzStorageContainerSASToken -Name $containerName -Policy $sasPolicy -Context $storageAccount.Context


# Store the SAS token in the SRE keyvault
# ---------------------------------------
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.accessPolicies.researcher.sasSecretName -DefaultValue $newSAStoken


# Ensure that private endpoint exists
# -----------------------------------
$privateEndpointName = "$($storageAccount.Context.Name)-endpoint"
$privateDnsZoneName = "$($storageAccount.Context.Name).blob.core.windows.net".ToLower()
$privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$($privateEndpointName)ServiceConnection" -PrivateLinkServiceId $storageAccount.Id -GroupId $config.sre.storage.datastorage.containers.ingress.storageType
$privateEndpoint = Get-AzPrivateEndpoint -Name $privateEndpointName -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction SilentlyContinue
if ($privateEndpoint) {
    Add-LogMessage -Level Warning "Removing existing private endpoint '$($privateEndpointName)'"
    Remove-AzPrivateEndpoint -Name $privateEndpointName -ResourceGroupName $config.sre.network.vnet.rg -Force
}
Add-LogMessage -Level Info "Creating private endpoint '$($privateEndpointName)' to resource '$($storageAccount.context.name)'"
$virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name
($virtualNetwork | Select-Object -ExpandProperty Subnets | Where-Object  {$_.Name -eq 'SharedDataSubnet'} ).PrivateEndpointNetworkPolicies = "Disabled"
$virtualNetwork | Set-AzVirtualNetwork

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
$privateip = (Get-AzNetworkInterface -ResourceId $($privateEndpoint.NetworkInterfaces.id)).IpConfigurations[0].PrivateIpAddress


# Set up DNS zone
# ---------------
Add-LogMessage -Level Info "Setting up DNS Zone"
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$params = @{
    ZoneName  = $privateDnsZoneName
    ipaddress = $privateip
    update    = ($dnsForceUpdate ? "force" : "non forced")

}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_storage" "set_dns_zone.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -vmName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
