$resourceGroupName = 'RESOURCEGROUP' # Key Vault Resourse group
$keyVaultName = 'KEYVAULT' # Key Vault Name
$keyVaultLocation = 'UK South'
$aadSvcPrinAppDisplayName = 'APPLICATION NAME' # Name of AAD Enterprise application used by encryption service
$keyName = 'KEYNAME' # Key Vault Key Name
$keyType = 'Software' # Key Vault Key Type

#Select subscription
write-Host -ForegroundColor Cyan "Select the correct subscription..."
$subscription = (
    Get-AzureRmSubscription |
    Sort-Object -Property Name |
    Select-Object -Property Name,Id |
    Out-GridView -OutputMode Single -Title 'Select an subscription'
).name

Select-AzureRmSubscription -SubscriptionName $subscription
write-Host -ForegroundColor Green "Ok, lets go!"

Read-Host -Prompt "Check that the subscription has been selected above, press any key to continue or Ctrl+C to abort"

#Register Key Vault Resource Provider
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.KeyVault"

#Pausing the script, if the new services vault command fails give restart the script from here.
Write-Host "Script paused for 180 seconds....." -ForegroundColor Cyan
Start-Sleep -Seconds 180
Write-Host "Ok, lets go!" -ForegroundColor Green


#Create Azure Key Vault
write-Host -ForegroundColor Cyan "Creating Azure Key Vault...."
New-AzureRmResourceGroup –Name $resourceGroupName –Location $keyVaultLocation

New-AzureRmKeyVault      -VaultName $keyVaultName `
                         -ResourceGroupName $resourceGroupName `
                         -Location $keyVaultLocation `
                         -Sku 'Standard'

Write-Host -ForegroundColor Green "Done!"

#Permit the Azure Backup service to access the key vault
write-Host -ForegroundColor Cyan "Configuring Azure Vault Access Policy to Allow Backup Service Access..."
Set-AzureRmKeyVaultAccessPolicy     -VaultName $keyVaultName `
                                    -ResourceGroupName $resourceGroupName `
                                    -PermissionsToKeys backup,get,list `
                                    -PermissionsToSecrets get,list `
                                    -ServicePrincipalName 262044b1-e2ce-469f-a196-69ab7ada62d3
Write-Host -ForegroundColor Green "Done!"

#Allow the Service Principal Permissions to the Key Vault
write-Host -ForegroundColor Cyan "Configuring Azure Vault Access Policy..."
$aadSvcPrinApplication = Get-AzureRmADApplication -DisplayName $aadSvcPrinAppDisplayName
Set-AzureRmKeyVaultAccessPolicy -VaultName $keyVaultName `
                                -ServicePrincipalName $aadSvcPrinApplication.ApplicationId `
                                -PermissionsToKeys 'WrapKey' `
                                -PermissionsToSecrets 'Set' `
                                -ResourceGroupName $resourceGroupName
Write-Host -ForegroundColor Green "Done!"

#Create KEK in the Key Vault
write-Host -ForegroundColor Cyan "Adding Azure Vault Key..."
Add-AzureKeyVaultKey    -VaultName $keyVaultName `
                        -Name $keyName `
                        -Destination $keyType
Write-Host -ForegroundColor Green "Done!"

#Allow Azure platform access to the KEK
write-Host -ForegroundColor Cyan "Setting Azure Vault Policy..."
Set-AzureRmKeyVaultAccessPolicy     -VaultName $keyVaultName `
                                    -ResourceGroupName $resourceGroupName `
                                    -EnabledForDiskEncryption
Write-Host -ForegroundColor Green "Done!"