#DC
$vm1RGName = 'RESOURCEGROUP' # Resource group of the VM
$vm1VmName = 'VMNAME' # Name of the VM

#Data server
$vm2RGName = 'RESOURCEGROUP' # Resource group of the VM
$vm2VmName = 'VMNAME' # Name of the VM

#RDS
$vm3RGName = 'RESOURCEGROUP' # Resource group of the VM
$vm3VmName = 'VMNAME' # Name of the VM

#RDSSH1
$vm4RGName = 'RESOURCEGROUP' # Resource group of the VM
$vm4VmName = 'VMNAME' # Name of the VM

#RDSSH2
$vm5RGName = 'RESOURCEGROUP' # Resource group of the VM
$vm5VmName = 'VMNAME' # Name of the VM

#NPS
$vm6RGName = 'RESOURCEGROUP' # Resource group of the VM
$vm6VmName = 'VMNAME' # Name of the VM


#General settings
$Location = 'uksouth'
$ExtensionName = 'MicrosoftMonitoringAgent'
$Publisher = 'Microsoft.EnterpriseCloud.Monitoring'
$Version = '1.0'

$PublicConf = '{ "workspaceId": "ID", "stopOnMultipleConnections": false }' # Update workspace ID from OMS
$PrivateConf = '{ "workspaceKey": "KEY" }'  # Updae workspace key from OMS

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

#Install OMS extension on VM
write-Host -ForegroundColor Cyan "Configuring VM...."
Set-AzureRmVMExtension  -ResourceGroupName $vm1RGName `
                        -VMName $vm1VmName `
                        -Location $Location `
                        -Name $ExtensionName `
                        -Publisher $Publisher `
                        -ExtensionType $ExtensionName `
                        -TypeHandlerVersion $Version `
                        -Settingstring $PublicConf `
                        -ProtectedSettingString $PrivateConf
write-Host -ForegroundColor Green "Done!"

#Install OMS extension on VM
write-Host -ForegroundColor Cyan "Configuring VM...."
Set-AzureRmVMExtension  -ResourceGroupName $vm2RGName `
                        -VMName $vm2VmName `
                        -Location $Location `
                        -Name $ExtensionName `
                        -Publisher $Publisher `
                        -ExtensionType $ExtensionName `
                        -TypeHandlerVersion $Version `
                        -Settingstring $PublicConf `
                        -ProtectedSettingString $PrivateConf
write-Host -ForegroundColor Green "Done!"

#Install OMS extension on VM server
write-Host -ForegroundColor Cyan "Configuring VM...."
Set-AzureRmVMExtension  -ResourceGroupName $vm3RGName `
                        -VMName $vm3VmName `
                        -Location $Location `
                        -Name $ExtensionName `
                        -Publisher $Publisher `
                        -ExtensionType $ExtensionName `
                        -TypeHandlerVersion $Version `
                        -Settingstring $PublicConf `
                        -ProtectedSettingString $PrivateConf
write-Host -ForegroundColor Green "Done!"

#Install OMS extension on VM server
write-Host -ForegroundColor Cyan "Configuring VM...."
Set-AzureRmVMExtension  -ResourceGroupName $vm4RGName `
                        -VMName $vm4VmName `
                        -Location $Location `
                        -Name $ExtensionName `
                        -Publisher $Publisher `
                        -ExtensionType $ExtensionName `
                        -TypeHandlerVersion $Version `
                        -Settingstring $PublicConf `
                        -ProtectedSettingString $PrivateConf
write-Host -ForegroundColor Green "Done!"

#Install OMS extension on VM server
write-Host -ForegroundColor Cyan "Configuring VM...."
Set-AzureRmVMExtension  -ResourceGroupName $vm5RGName `
                        -VMName $vm5VmName `
                        -Location $Location `
                        -Name $ExtensionName `
                        -Publisher $Publisher `
                        -ExtensionType $ExtensionName `
                        -TypeHandlerVersion $Version `
                        -Settingstring $PublicConf `
                        -ProtectedSettingString $PrivateConf
write-Host -ForegroundColor Green "Done!"

#Install OMS extension on VM 
write-Host -ForegroundColor Cyan "Configuring VM...."
Set-AzureRmVMExtension  -ResourceGroupName $vm6RGName `
                        -VMName $vm6VmName `
                        -Location $Location `
                        -Name $ExtensionName `
                        -Publisher $Publisher `
                        -ExtensionType $ExtensionName `
                        -TypeHandlerVersion $Version `
                        -Settingstring $PublicConf `
                        -ProtectedSettingString $PrivateConf
write-Host -ForegroundColor Green "Done!"