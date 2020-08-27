param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName


foreach ($accessPolicy in $config.sre.storage.accessPolicies) {
    write-host ($accessPolicy | Out-String)
    write-host "Key: $($accessPolicy.Key)"
    write-host "Value: $($accessPolicy.Value)"
}
exit 1


# Ensure that a container exists in the correct SHM storage account for this SRE
# ------------------------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.datastorage.rg -Location $config.shm.location
$storageAccount = Deploy-StorageAccount -Name $config.sre.storage.datastorage.accountName -ResourceGroupName $config.sre.storage.datastorage.rg -Kind $config.sre.storage.datastorage.storageType -Location $config.shm.location -SkuName "Standard_RAGRS"
if (-not $storageAccount.PrimaryEndpoints.Blob) {
    Add-LogMessage -Level Fatal "Storage account '$($config.sre.storage.datastorage.accountName)' does not support blob storage!"
}
$containerName = $config.sre.storage.datastorage.containers.ingress.name
$null = Deploy-StorageContainer -Name $containerName -StorageAccount $storageAccount


# Create a new SAS token (and policy if required) then store it in the SRE keyvault
# ---------------------------------------------------------------------------------
$sasPolicy = Deploy-SasAccessPolicy -Name $config.sre.accessPolicies.researcher.nameSuffix `
                                    -Permission $config.sre.accessPolicies.researcher.permissions `
                                    -StorageAccount $storageAccount `
                                    -ContainerName $containerName `
                                    -ValidityYears 1
$newSAStoken = New-AzStorageContainerSASToken -Name $containerName -Policy $sasPolicy -Context $storageAccount.Context
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.accessPolicies.researcher.sasSecretName -DefaultValue $newSAStoken


# # Disable private endpoint network policies on the data subnet
# # ------------------------------------------------------------
# $dataSubnetName = $config.sre.network.vnet.subnets.data.name
# $virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name
# ($virtualNetwork | Select-Object -ExpandProperty Subnets | Where-Object  {$_.Name -eq $dataSubnetName }).PrivateEndpointNetworkPolicies = "Disabled"
# $virtualNetwork | Set-AzVirtualNetwork
# $dataSubnet = Get-AzSubnet -Name $dataSubnetName -VirtualNetwork $virtualNetwork


# Ensure that private endpoint exists
# -----------------------------------
$dataSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.data.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
# $privateEndpoint = Deploy-StorageAccountEndpoint -StorageAccount $storageAccount -StorageType $config.sre.storage.datastorage.containers.ingress.storageType -Subnet $dataSubnet -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
$privateEndpoint = Deploy-StorageAccountEndpoint -StorageAccount $storageAccount -Subnet $dataSubnet -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
$privateEndpointIp = (Get-AzNetworkInterface -ResourceId $privateEndpoint.NetworkInterfaces.Id).IpConfigurations[0].PrivateIpAddress


# Set up DNS zone
# ---------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$privateDnsZoneName = "$($storageAccount.StorageAccountName).blob.core.windows.net".ToLower()




Add-LogMessage -Level Info "Setting up DNS Zone for '$privateDnsZoneName'"
$params = @{
    Name = $privateDnsZoneName
    IpAddress = $privateEndpointIp
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_storage" "Set_DNS_Zone.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -vmName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
