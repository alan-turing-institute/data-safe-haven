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
$null = Update-AzStorageAccountNetworkRuleSet -Name $config.sre.storage.persistentdata.account.name -ResourceGroupName $config.shm.storage.persistentdata.rg -DefaultAction Allow
Start-Sleep 10
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Set up containers for persistent data in the SHM
# These are Blob storage mounted over SMB
# ------------------------------------------------
if (-not $persistentStorageAccount.PrimaryEndpoints.Blob) {
    Add-LogMessage -Level Fatal "Storage account '$($config.sre.storage.persistentdata.account.name)' does not support blob storage!"
}
foreach ($receptacleName in $config.sre.storage.persistentdata.containers.Keys) {
    # When using blob storage we need to mount using a SAS token
    if ($config.sre.storage.persistentdata.containers[$receptacleName].mountType -eq "BlobSMB") {
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

        # As we want to ensure that the SAS token is valid for 1 year from *now* we do not want to re-use old tokens
        # We therefore always generate a new token and store it in the keyvault (note that old tokens will still be valid and will still be stored as old versions of the secret)
        # Note that this also protects us against the case when a SAS token corresponding to an old storage receptacle has been stored in the key vault
        $sasToken = New-StorageReceptacleSasToken -ContainerName $receptacleName -Policy $sasPolicy.Policy -StorageAccount $persistentStorageAccount
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers[$receptacleName].connectionSecretName -DefaultValue $sasToken -AsPlaintext -ForceOverwrite

    # When using a file share we need to mount using the storage key
    } elseif ($config.sre.storage.persistentdata.containers[$receptacleName].mountType -eq "ShareSMB") {
        # Deploy the share
        $null = Deploy-StorageReceptacle -Name $receptacleName -StorageAccount $persistentStorageAccount -StorageType "Share"

        # Ensure that the appropriate storage key is stored in the SRE keyvault
        $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $config.shm.storage.persistentdata.rg -Name $config.sre.storage.persistentdata.account.name | Where-Object {$_.KeyName -eq "key1"}).Value
        $null = Set-AzContext -SubscriptionId $config.sre.subscriptionName
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers[$receptacleName].connectionSecretName -DefaultValue $storageKey -AsPlaintext -ForceOverwrite
    }
}


# Add a private endpoint for the storage account
# ----------------------------------------------
$dataSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.data.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
Add-LogMessage -Level Info "Setting up private endpoint for '$($persistentStorageAccount.StorageAccountName)'"
$privateEndpoint = Deploy-StorageAccountEndpoint -StorageAccount $persistentStorageAccount -StorageType "Default" -Subnet $dataSubnet -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
$privateEndpointIp = (Get-AzNetworkInterface -ResourceId $privateEndpoint.NetworkInterfaces.Id).IpConfigurations[0].PrivateIpAddress
$privateDnsZoneName = "$($persistentStorageAccount.StorageAccountName).blob.core.windows.net".ToLower()


# Ensure that public access to the storage account is only allowed from approved locations
# ----------------------------------------------------------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName
$null = Update-AzStorageAccountNetworkRuleSet -Name $config.sre.storage.persistentdata.account.name -ResourceGroupName $config.shm.storage.persistentdata.rg -DefaultAction Deny
foreach ($IpAddress in $config.sre.storage.persistentdata.account.allowedIpAddresses) {
    $null = Add-AzStorageAccountNetworkRule -AccountName $config.sre.storage.persistentdata.account.name -ResourceGroupName $config.shm.storage.persistentdata.rg -IPAddressOrRange $IpAddress
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName


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
