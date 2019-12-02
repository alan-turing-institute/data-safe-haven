$resourceGroupName = "RESOURCEGROUP" # Resource group for recovery service
$Location = "uksouth"
$RSVName = "NAME" # Recovery Service name
$StorageRedundancyLRS = "LocallyRedundant"

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


#Create Resource Group
write-Host -ForegroundColor Cyan "Creating Resource Group..."
New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
write-Host -ForegroundColor Green "Resource Group Created"

#Register the Azure Recovery Service provider with your Azure subscription
Write-Host "Registering with recovery services...." -ForegroundColor Cyan
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.RecoveryServices"
Write-Host "Registered"

#Pausing the script, if the new services vault command fails give restart the script from here.
Write-Host "Script paused for 180 seconds....." -ForegroundColor Cyan
Start-Sleep -Seconds 180
Write-Host "Ok, lets go!" -ForegroundColor Green

#Create the Recovery Services vault
Write-Host "Creating recovery services" -ForegroundColor Cyan
New-AzureRmRecoveryServicesVault -Name $RSVName -ResourceGroupName $resourceGroupName -Location $Location
Write-Host "Recovery services created" -ForegroundColor Green

#Specify the type of storage redundancy for the Recovery Services vault
Write-Host "Configuring recovery services..." -ForegroundColor Cyan
$VarRSV = Get-AzureRmRecoveryServicesVault –Name $RSVName
Set-AzureRmRecoveryServicesBackupProperties -Vault $VarRSV -BackupStorageRedundancy $StorageRedundancyLRS
Get-AzureRmRecoveryServicesVault -Name $RSVName | Set-AzureRmRecoveryServicesVaultContext

Write-Host "Recovery Serives configured" -foregroundcolor "Green"

#Add servers to backup
Write-Host "Adding servers to recovery services..." -ForegroundColor Cyan
$pol=Get-AzureRmRecoveryServicesBackupProtectionPolicy -Name "DefaultPolicy"
Write-Host "Adding Domain Controller..." -ForegroundColor Cyan
Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name "VMNAME" -ResourceGroupName "RESOURCEGROUP"
Write-Host "Adding RDS Gateway..." -ForegroundColor Cyan
Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name "VMNAME" -ResourceGroupName "RESOURCEGROUP"
Write-Host "Adding RDS Session Host 1..." -ForegroundColor Cyan
Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name "VMNAME" -ResourceGroupName "RESOURCEGROUP"
Write-Host "Adding RDS Session Host 2..." -ForegroundColor Cyan
Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name "VMNAME" -ResourceGroupName "RESOURCEGROUP"
Write-Host "Adding Network Policy Server..." -ForegroundColor Cyan
Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name "VMNAME" -ResourceGroupName "RESOURCEGROUP"
Write-Host "Adding Data Server..." -ForegroundColor Cyan
Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name "VMNAME" -ResourceGroupName "RESOURCEGROUP"
Write-Host "Adding Jupyter Server..." -ForegroundColor Cyan
Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name "VMNAME" -ResourceGroupName "RESOURCEGROUP"
Write-Host "Adding Git Lab Server..." -ForegroundColor Cyan
Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name "VMNAME" -ResourceGroupName "RESOURCEGROUP"
Write-Host "Adding HackMD Server..." -ForegroundColor Cyan
Enable-AzureRmRecoveryServicesBackupProtection -Policy $pol -Name "VMNAME" -ResourceGroupName "RESOURCEGROUP"
Write-Host "Servers added!" -foregroundcolor "Green"
