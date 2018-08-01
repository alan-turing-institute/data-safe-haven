#Parameters
param (
    [string][Parameter(Mandatory=$true)]$VNNname,
    [string][Parameter(Mandatory=$true)]$VMResourceGroup
    )

#Input Area
$resourceGroupName = 'RESOURCEGROUP' # Key Vault Resource Group
$keyVaultName = 'KEYVAULT' # Key Vault Name
$keyVaultLocation = 'UK South'
$aadSvcPrinAppDisplayName = 'APPLICATION NAME' # Name of AAD Enterprise application used by encryption service
$keyName = 'KEYNAME' # Key Vault Key Name
$aadSvcPrinAppPassword = 'PASSWORD' # AAD Enterprise application secret

#Set subscription
Select-AzureRmSubscription -SubscriptionName "SUBSCRIPTION NAME" # Enter subscription name

#Enable Encryption on Virtual Machine
Write-Host "Encrypting VM $VMName ....." -ForegroundColor Cyan
$keyVault = Get-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroupName
$diskEncryptionKeyVaultUrl = $KeyVault.VaultUri
$keyVaultResourceId = $KeyVault.ResourceId
$keyEncryptionKeyUri = Get-AzureKeyVaultKey -VaultName $keyVaultName -KeyName $keyName 
$aadSvcPrinApplication = Get-AzureRmADApplication -DisplayName $aadSvcPrinAppDisplayName 

Set-AzureRmVMDiskEncryptionExtension    -ResourceGroupName $VMResourceGroup `
                                        -VMName $VNNname `
                                        -AadClientID $aadSvcPrinApplication.ApplicationId `
                                        -AadClientSecret $aadSvcPrinAppPassword `
                                        -DiskEncryptionKeyVaultUrl $diskEncryptionKeyVaultUrl `
                                        -DiskEncryptionKeyVaultId $KeyVaultResourceId `
                                        -KeyEncryptionKeyUrl $keyEncryptionKeyUri.Id `
                                        -KeyEncryptionKeyVaultId $keyVaultResourceId `
                                        -Verbose `
                                        -Force
Write-Host -ForegroundColor Green "Done!"