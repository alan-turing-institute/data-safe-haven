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
$null = Deploy-ResourceGroup -Name $config.shm.storage.persistentdata.rg -Location $config.shm.location
$persistentStorageAccount = Deploy-StorageAccount -Name $config.sre.storage.persistentdata.account.name `
                                                  -AccessTier $config.sre.storage.persistentdata.account.accessTier `
                                                  -Kind $config.sre.storage.persistentdata.account.storageKind `
                                                  -Location $config.shm.location `
                                                  -ResourceGroupName $config.shm.storage.persistentdata.rg `
                                                  -SkuName $config.sre.storage.persistentdata.account.performance
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Set up containers for persistent data in the SHM
# These are Blob storage mounted over SMB
# ------------------------------------------------
if (-not $persistentStorageAccount.PrimaryEndpoints.Blob) {
    Add-LogMessage -Level Fatal "Storage account '$($config.sre.storage.persistentdata.account.name)' does not support blob storage!"
}
foreach ($receptacleName in $config.sre.storage.persistentdata.containers.Keys) {
    # Ensure that we are using SMB
    if ($config.sre.storage.persistentdata.containers[$receptacleName].mountType -ne "SMB") {
        Add-LogMessage -Level Fatal "Currently only blob-storage mounted over SMB is supported for the persistent '$receptacleName' container!"
    }

    # Deploy the container
    $null = Deploy-StorageReceptacle -Name $receptacleName -StorageAccount $persistentStorageAccount -StorageType "Container"

    # As this is a blob container, we need to access it using a SAS token and a private endpoint
    # Ensure that the appropriate SAS policy exists
    $accessPolicyName = $config.sre.storage.persistentdata.containers[$receptacleName].accessPolicyName
    $sasPolicy = Deploy-SasAccessPolicy -Name $accessPolicyName `
                                        -Permission $config.sre.storage.accessPolicies[$accessPolicyName].permissions `
                                        -StorageAccount $persistentStorageAccount `
                                        -ContainerName $receptacleName `
                                        -ValidityYears 1

    # If there is no SAS token in the SRE keyvault then create one and store it there
    if (Get-AzKeyVaultSecret -VaultName $config.sre.keyVault.name -Name $config.sre.storage.persistentdata.containers[$receptacleName].sasSecretName) {
        Add-LogMessage -Level InfoSuccess "Found existing SAS token '$($config.sre.storage.persistentdata.containers[$receptacleName].sasSecretName)' for container '$receptacleName' in '$($persistentStorageAccount.StorageAccountName)"
    } else {
        $sasToken = New-StorageReceptacleSasToken -ContainerName $receptacleName -Policy $sasPolicy.Policy -StorageAccount $persistentStorageAccount
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers[$receptacleName].sasSecretName -DefaultValue $sasToken
    }
}


# Ensure that the storage accounts can only be accessed through private endpoints
# -------------------------------------------------------------------------------
$dataSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.data.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
Add-LogMessage -Level Info "Setting up private endpoint for '$($persistentStorageAccount.StorageAccountName)'"
$privateEndpoint = Deploy-StorageAccountEndpoint -StorageAccount $persistentStorageAccount -StorageType "Default" -Subnet $dataSubnet -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
$privateEndpointIp = (Get-AzNetworkInterface -ResourceId $privateEndpoint.NetworkInterfaces.Id).IpConfigurations[0].PrivateIpAddress
$privateDnsZoneName = "$($persistentStorageAccount.StorageAccountName).blob.core.windows.net".ToLower()


# Set up a DNS zone on the SHM DC
# -------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "Setting up DNS zone '$privateDnsZoneName'"
$params = @{
    Name      = $privateDnsZoneName
    IpAddress = $privateEndpointIp
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_storage" "Set_DNS_Zone.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -vmName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
