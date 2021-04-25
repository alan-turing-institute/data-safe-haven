param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/AzureStorage.psm1 -Force
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/DataStructures.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Ensure that a storage account exists in the SHM for this SRE
# ------------------------------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
$null = Deploy-ResourceGroup -Name $config.shm.storage.persistentdata.rg -Location $config.shm.location
$persistentStorageAccount = Deploy-StorageAccount -Name $config.sre.storage.persistentdata.account.name `
                                                  -AccessTier $config.sre.storage.persistentdata.account.accessTier `
                                                  -Kind $config.sre.storage.persistentdata.account.storageKind `
                                                  -Location $config.shm.location `
                                                  -ResourceGroupName $config.shm.storage.persistentdata.rg `
                                                  -SkuName $config.sre.storage.persistentdata.account.performance
# Add a temporary override during deployment
$null = Update-AzStorageAccountNetworkRuleSet -Name $config.sre.storage.persistentdata.account.name -ResourceGroupName $config.shm.storage.persistentdata.rg -DefaultAction Allow
Start-Sleep 30
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Set up containers for persistent data in the SHM
# These are Blob storage mounted over SMB
# ------------------------------------------------
if (-not $persistentStorageAccount.PrimaryEndpoints.Blob) {
    Add-LogMessage -Level Fatal "Storage account '$($config.sre.storage.userdata.account.name)' does not support blob storage! If you attempted to override this setting in your config file, please remove this change."
}
foreach ($receptacleName in $config.sre.storage.persistentdata.containers.Keys) {
    if ($config.sre.storage.persistentdata.containers[$receptacleName].mountType -notlike "*SMB*") {
        Add-LogMessage -Level Fatal "Currently only file storage mounted over SMB is supported for the '$receptacleName' container! If you attempted to override this setting in your config file, please remove this change."
    }

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
        # We therefore always generate a new token and store it in the Key Vault (note that old tokens will still be valid and will still be stored as old versions of the secret)
        # Note that this also protects us against the case when a SAS token corresponding to an old storage receptacle has been stored in the Key Vault
        $sasToken = New-StorageReceptacleSasToken -ContainerName $receptacleName -PolicyName $sasPolicy.Policy -StorageAccount $persistentStorageAccount
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers[$receptacleName].connectionSecretName -DefaultValue $sasToken -AsPlaintext -ForceOverwrite

    # When using a file share we need to mount using the storage key
    } elseif ($config.sre.storage.persistentdata.containers[$receptacleName].mountType -eq "ShareSMB") {
        # Deploy the share
        $null = Deploy-StorageReceptacle -Name $receptacleName -StorageAccount $persistentStorageAccount -StorageType "Share"

        # Ensure that the appropriate storage key is stored in the SRE Key Vault
        $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
        $storageKey = (Get-AzStorageAccountKey -ResourceGroupName $config.shm.storage.persistentdata.rg -Name $config.sre.storage.persistentdata.account.name | Where-Object { $_.KeyName -eq "key1" }).Value
        $null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
        $null = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers[$receptacleName].connectionSecretName -DefaultValue $storageKey -AsPlaintext -ForceOverwrite
    }
}


# Set up containers for user data in the SRE
# These are Files storage mounted over NFS
# Note that we *must* register the NFS provider before creating the storage account:
#   https://docs.microsoft.com/en-us/azure/storage/files/storage-troubleshooting-files-nfs#cause-3-the-storage-account-was-created-prior-to-registration-completing
# -----------------------------------------------------------------------------------------------------------------------------------------------------------------
# Register NFS provider
if ((Get-AzProviderFeature -FeatureName AllowNfsFileShares -ProviderNamespace Microsoft.Storage).RegistrationState -eq "NotRegistered") {
    $null = Register-AzProviderFeature -FeatureName AllowNfsFileShares -ProviderNamespace Microsoft.Storage
    $null = Register-AzResourceProvider -ProviderNamespace Microsoft.Storage
}
# Wait until registration is complete
$progress = 0
$registrationState = (Get-AzProviderFeature -FeatureName AllowNfsFileShares -ProviderNamespace Microsoft.Storage).RegistrationState
while ($registrationState -ne "Registered") {
    $registrationState = (Get-AzProviderFeature -FeatureName AllowNfsFileShares -ProviderNamespace Microsoft.Storage).RegistrationState
    $progress = [math]::min(100, $progress + 1)
    Write-Progress -Activity "Registering NFS feature in '$((Get-AzContext).Subscription.Name)' subscription" -Status $registrationState -PercentComplete $progress
    Start-Sleep 30
}
$null = Deploy-ResourceGroup -Name $config.sre.storage.userdata.account.rg -Location $config.sre.location
# Note that we disable the https requirement as per the Azure documentation:
#   "Double encryption is not supported for NFS shares yet. Azure provides a
#   layer of encryption for all data in transit between Azure datacenters
#   using MACSec. NFS shares can only be accessed from trusted virtual
#   networks and over VPN tunnels. No additional transport layer encryption
#   is available on NFS shares."
$userdataStorageAccount = Deploy-StorageAccount -Name $config.sre.storage.userdata.account.name `
                                                -AccessTier $config.sre.storage.userdata.account.accessTier `
                                                -Kind $config.sre.storage.userdata.account.storageKind `
                                                -Location $config.sre.location `
                                                -ResourceGroupName $config.sre.storage.userdata.account.rg `
                                                -SkuName $config.sre.storage.userdata.account.performance `
                                                -AllowHttpTraffic
# Add a temporary override during deployment
$null = Update-AzStorageAccountNetworkRuleSet -Name $config.sre.storage.userdata.account.name -ResourceGroupName $config.sre.storage.userdata.account.rg -DefaultAction Allow
Start-Sleep 30


# Ensure that all required userdata containers exist
# --------------------------------------------------
if (-not $userdataStorageAccount.PrimaryEndpoints.File) {
    Add-LogMessage -Level Fatal "Storage account '$($config.sre.storage.userdata.account.name)' does not support file storage! If you attempted to override this setting in your config file, please remove this change."
}
foreach ($receptacleName in $config.sre.storage.userdata.containers.Keys) {
    # Ensure that we are using NFS
    if ($config.sre.storage.userdata.containers[$receptacleName].mountType -ne "NFS") {
        Add-LogMessage -Level Fatal "Currently only file-storage mounted over NFS is supported for the '$receptacleName' container! If you attempted to override this setting in your config file, please remove this change."
    }
    # Deploy the share and set its quota
    $null = Deploy-StorageReceptacle -Name $receptacleName -StorageAccount $userdataStorageAccount -StorageType "NfsShare"
    $null = Set-StorageNfsShareQuota -Name $receptacleName -Quota $config.sre.storage.userdata.containers[$receptacleName].sizeGb -StorageAccount $userdataStorageAccount
}


# Ensure that SRE artifacts storage account exists
# ------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.storage.artifacts.rg -Location $config.sre.location
$artifactsStorageAccount = Deploy-StorageAccount -Name $config.sre.storage.artifacts.account.name `
                                                 -AccessTier $config.sre.storage.artifacts.account.accessTier `
                                                 -Kind $config.sre.storage.artifacts.account.storageKind `
                                                 -Location $config.sre.location `
                                                 -ResourceGroupName $config.sre.storage.artifacts.rg `
                                                 -SkuName $config.sre.storage.artifacts.account.performance
# Add a temporary override during deployment
$null = Update-AzStorageAccountNetworkRuleSet -Name $config.sre.storage.artifacts.account.name -ResourceGroupName $config.sre.storage.artifacts.rg -DefaultAction Allow
Start-Sleep 30


# Ensure that the storage accounts can be accessed from the SRE VNet through private endpoints
# --------------------------------------------------------------------------------------------
$dataSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.data.name -VirtualNetworkName $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg
foreach ($storageAccount in @($persistentStorageAccount, $userdataStorageAccount, $artifactsStorageAccount)) {
    # Set up a private endpoint
    Add-LogMessage -Level Info "Setting up private endpoint for '$($storageAccount.StorageAccountName)'"
    $privateEndpoint = Deploy-StorageAccountEndpoint -StorageAccount $storageAccount -StorageType "Default" -Subnet $dataSubnet -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
    $privateEndpointIp = (Get-AzNetworkInterface -ResourceId $privateEndpoint.NetworkInterfaces.Id).IpConfigurations[0].PrivateIpAddress
    $privateEndpointFqdns = Get-StorageAccountEndpoints -StorageAccount $storageAccount | ForEach-Object { $_.Split("/")[2] } # we want only the FQDN without protocol or trailing slash
    # Set up a DNS zone on the SHM DC
    $null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
    Add-LogMessage -Level Info "Setting up DNS zones for: $privateEndpointFqdns"
    $params = @{
        privateEndpointFqdnsB64 = $privateEndpointFqdns | ConvertTo-Json | ConvertTo-Base64
        IpAddress               = $privateEndpointIp
    }
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_storage" "Set_DNS_Zone.ps1"
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -vmName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
    $null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
}


# Ensure that public access to the storage accounts is only allowed from approved locations
# -----------------------------------------------------------------------------------------
# Persistent data - allow access from approved IP addresses
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
$null = Update-AzStorageAccountNetworkRuleSet -Name $config.sre.storage.persistentdata.account.name -ResourceGroupName $config.shm.storage.persistentdata.rg -DefaultAction Deny
foreach ($IpAddress in $config.sre.storage.persistentdata.account.allowedIpAddresses) {
    $null = Add-AzStorageAccountNetworkRule -AccountName $config.sre.storage.persistentdata.account.name -ResourceGroupName $config.shm.storage.persistentdata.rg -IPAddressOrRange $IpAddress
}
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop
# Build artifacts - allow access from approved IP addresses
if ($config.sre.storage.artifacts.account.allowedIpAddresses -eq "any") {
    $null = Update-AzStorageAccountNetworkRuleSet -Name $config.sre.storage.artifacts.account.name -ResourceGroupName $config.sre.storage.artifacts.rg -DefaultAction Allow
} else {
    $null = Update-AzStorageAccountNetworkRuleSet -Name $config.sre.storage.artifacts.account.name -ResourceGroupName $config.sre.storage.artifacts.rg -DefaultAction Deny
    foreach ($IpAddress in $config.sre.storage.artifacts.account.allowedIpAddresses) {
        $null = Add-AzStorageAccountNetworkRule -AccountName $config.sre.storage.artifacts.account.name -ResourceGroupName $config.sre.storage.artifacts.rg -IPAddressOrRange $IpAddress
    }
}
# User data - deny all access
$null = Update-AzStorageAccountNetworkRuleSet -Name $config.sre.storage.userdata.account.name -ResourceGroupName $config.sre.storage.userdata.account.rg -DefaultAction Deny


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
