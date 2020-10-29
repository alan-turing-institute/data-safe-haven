param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/AzureStorage.psm1 -Force
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Ensure that a storage account exists in the SHM for this SRE
# ------------------------------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$null = Deploy-ResourceGroup -Name $config.shm.storage.data.rg -Location $config.shm.location
$storageAccount = Deploy-StorageAccount -Name $config.sre.storage.data.account.name `
                                        -AccessTier $config.sre.storage.data.account.accessTier `
                                        -Kind $config.sre.storage.data.account.storageKind `
                                        -Location $config.shm.location `
                                        -ResourceGroupName $config.shm.storage.data.rg `
                                        -SkuName "Standard_RAGRS"
if (-not $storageAccount.PrimaryEndpoints.Blob) {
    Add-LogMessage -Level Fatal "Storage account '$($config.sre.storage.data.accountName)' does not support blob storage!"
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Ensure that all required containers exist
# -----------------------------------------
foreach ($containerName in $config.sre.storage.data.containers.Keys) {
    # Deploy the container
    $null = Deploy-StorageContainer -Name $containerName -StorageAccount $storageAccount

    # Ensure that the appropriate SAS policy exists
    $accessPolicyName = $config.sre.storage.data.containers[$containerName].accessPolicyName
    $sasPolicy = Deploy-SasAccessPolicy -Name $accessPolicyName `
                                        -Permission $config.sre.storage.accessPolicies[$accessPolicyName].permissions `
                                        -StorageAccount $storageAccount `
                                        -ContainerName $containerName `
                                        -ValidityYears 1

    # Create a new SAS token then store it in the SRE keyvault
    $newSAStoken = New-StorageReceptacleSasToken -ContainerName $containerName -Policy $sasPolicy -StorageAccount $storageAccount
    $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.data.containers[$containerName].sasSecretName -DefaultValue $newSAStoken
}


# Ensure that private endpoint exists
# -----------------------------------
$dataSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.data.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
$privateEndpoint = Deploy-StorageAccountEndpoint -StorageAccount $storageAccount -StorageType "Default" -Subnet $dataSubnet -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
$privateEndpointIp = (Get-AzNetworkInterface -ResourceId $privateEndpoint.NetworkInterfaces.Id).IpConfigurations[0].PrivateIpAddress


# Set up a DNS zone on the SHM DC
# -------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$privateDnsZoneName = "$($storageAccount.StorageAccountName).blob.core.windows.net".ToLower()
Add-LogMessage -Level Info "Setting up DNS Zone for '$privateDnsZoneName'"
$params = @{
    Name      = $privateDnsZoneName
    IpAddress = $privateEndpointIp
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_storage" "Set_DNS_Zone.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -vmName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
