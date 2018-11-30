#VM Settings
$publisher = "MicrosoftWindowsServer"
$offer = "WindowsServer"
$sku = "2019-Datacenter"
$vmsize = "Standard_D2s_v3"
$version = "latest"

#SHMDC1
$dc1osdiskSize = '128'
$dc1osdiskname = "SHMDC1_OS_Disk"
$dc1name = "SHMDC1"
$dc1nicname = "SHMDC1_NIC1"
$dc1ipaddress = "10.251.0.250"

#SHMDC2
$dc2osdiskSize = '128'
$dc2osdiskname = "SHMDC2_OS_Disk"
$dc2name = "SHMDC2"
$dc2nicname = "SHMDC2_NIC1"
$dc2ipaddress = "10.251.0.249"

#Diagnostics settings
$storagediagname = ('bbazdcdiag'+(Get-Random))
$storagediagsku = "Standard_LRS"

#Storage Type
$diskaccountType = "Premium_LRS"


#Resources
$resourceGroupName = "RG_SHM_VM_DC"
$location = "UK South"
$availabilityset = "AVSET_SHM_VM_DC"

#Select subscription
write-Host -ForegroundColor Cyan "Select the correct subscription..."
$subscription = (
    Get-AzureRmSubscription |
    Sort-Object -Property Name |
    Select-Object -Property Name,Id |
    Out-GridView -OutputMode Single -Title 'Select an subscription'
).name

Select-AzureRmSubscription -SubscriptionName $subscription
write-Host -ForegroundColor Green "Ok, got it!"

Read-Host -Prompt "Check that the subscription has been selected above, press enter key to continue or Ctrl+C to abort"

#Network
$vnetrg = "RG_SHM_VNet"
$subnetName = "Subnet-Identity"

#Select VNet
write-Host -ForegroundColor Cyan "Select the correct VNET..."
$vnetname = (
    Get-AzureRmVirtualNetwork -ResourceGroupName $vnetrg |
    Sort-Object -Property Name |
    Select-Object -Property Name,Id |
    Out-GridView -OutputMode Single -Title 'Select the correct VNet'
).name
write-Host -ForegroundColor Green "Ok, got it!"

# Enter credentials for new VM
write-Host -ForegroundColor Green "Enter credentials to be used for VMs local administrator account"
$cred = Get-Credential

# Create Resource Group for DC
write-Host -ForegroundColor Cyan "Creating Resource Group..."
New-AzureRmResourceGroup -Name $resourceGroupName -Location $location
write-Host -ForegroundColor Green "Resource Group Created"

# Connect to existing VNET
write-Host -ForegroundColor Cyan "Getting virtual network..."
$vnet = Get-AzureRmVirtualNetwork -Name $vnetname -ResourceGroupName $vnetrg
write-Host -ForegroundColor Green "Got it!"

# Select the subnet
write-Host -ForegroundColor Cyan "Getting subnet..."
$SubnetID = (Get-AzureRmVirtualNetworkSubnetConfig -Name $subnetname -VirtualNetwork $vnet).Id
write-Host -ForegroundColor Green "Got it!"

# Create new NICs in VNET
write-Host -ForegroundColor Cyan "Creating DC1 network interface..."
$dc1nic = New-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName `
        -Name $dc1nicname `
        -SubnetID $subnetID `
        -Location $location `
        -PrivateIpAddress $dc1ipaddress
write-Host -ForegroundColor Green "Network interface created"

write-Host -ForegroundColor Cyan "Creating DC2 network interface..."
$dc2nic = New-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName `
        -Name $dc2nicname `
        -SubnetID $subnetID `
        -Location $location `
        -PrivateIpAddress $dc2ipaddress
write-Host -ForegroundColor Green "Network interface created"

#Create managed data disks

#Create 20Gb disks for AD DBs
write-Host -ForegroundColor Cyan "Creating managed disk for DC1..."
$dc1datadisk1config = New-AzureRmDiskConfig     -Location $location `
                                                -DiskSizeGB 20 `
                                                -AccountType $diskaccountType `
                                                -OsType Windows `
                                                -CreateOption Empty

$dc1datadisk1 = New-AzureRmDisk     -ResourceGroupName $resourceGroupName `
                                    -DiskName ($dc1name+"_Data_Disk1") `
                                    -Disk $dc1datadisk1config
write-Host -ForegroundColor Green "Managed disk for DC1 created"

write-Host -ForegroundColor Cyan "Creating managed disk for DC2..."
$dc2datadisk1config = New-AzureRmDiskConfig     -Location $location `
                                                -DiskSizeGB 20 `
                                                -AccountType $diskaccountType `
                                                -OsType Windows `
                                                -CreateOption Empty

$dc2datadisk1 = New-AzureRmDisk     -ResourceGroupName $resourceGroupName `
                                    -DiskName ($dc2name+"_Data_Disk1") `
                                    -Disk $dc2datadisk1config
write-Host -ForegroundColor Green "Managed disk for DC2 created"

#Create availibility set
write-Host -ForegroundColor Cyan "Creating availability set..."
$avset = New-AzureRmAvailabilitySet -Location $location `
                                    -Name $availabilityset `
                                    -ResourceGroupName $resourceGroupName `
                                    -Sku aligned `
                                    -PlatformFaultDomainCount 2 `
                                    -PlatformUpdateDomainCount 2
write-Host -ForegroundColor Green "Availibility set created"

#Create Storage Account for boot diagnostics
write-Host -ForegroundColor Cyan "Creating diagnostic storage account..."
$storagediag = New-AzureRmStorageAccount -Location $location -Name $storagediagname -ResourceGroupName $resourcegroupname -SkuName $storagediagsku
write-Host -ForegroundColor Green "Diagnostic storage created"

#Create Domain Controllers
write-Host -ForegroundColor Cyan Creating $dc1name ...

$dc1vmConfig = New-AzureRmVMConfig         -VMName $dc1name `
                                           -VMSize $vmsize `
                                           -AvailabilitySetId $avset.id

$dc1vmConfig = Set-AzureRmVMOSDisk         -VM $dc1vmConfig `
                                           -Name $dc1osdiskname `
                                           -DiskSizeInGB $dc1osdiskSize `
                                           -StorageAccountType $diskaccountType `
                                           -CreateOption fromImage `
                                           -Windows  |

       Set-AzureRmVMOperatingSystem        -Windows `
                                           -ComputerName $dc1name `
                                           -Credential $cred `
                                           -ProvisionVMAgent `
                                           -EnableAutoUpdate  |

       Set-AzureRmVMSourceImage            -PublisherName $publisher `
                                           -Offer $offer `
                                           -Skus $sku `
                                           -Version $version |


       Add-AzureRmVMDataDisk               -Name $dc1datadisk1.Name `
                                           -CreateOption Attach `
                                           -ManagedDiskId $dc1datadisk1.id `
                                           -Lun 0 |

       Add-AzureRmVMNetworkInterface       -Id $dc1nic.Id -Primary |

       Set-AzureRmVMBootDiagnostics        -Enable `
                                           -ResourceGroupName $resourcegroupname `
                                           -StorageAccountName $storagediag.StorageAccountName

       New-AzureRmVM                       -ResourceGroupName $resourceGroupName `
                                           -Location $location `
                                           -LicenseType "Windows_Server" `
                                           -VM $dc1vmConfig

write-Host -ForegroundColor Green $dc1name Complete

# Create second DC
write-Host -ForegroundColor Cyan Creating $dc2name ...

$dc2vmConfig = New-AzureRmVMConfig         -VMName $dc2name `
                                           -VMSize $vmsize `
                                           -AvailabilitySetId $avset.id 
                                           
                                           
$dc2vmConfig = Set-AzureRmVMOSDisk         -VM $dc2vmConfig `
                                           -Name $dc2osdiskname `
                                           -DiskSizeInGB $dc2osdiskSize `
                                           -StorageAccountType $diskaccountType `
                                           -CreateOption fromImage `
                                           -Windows  |
                                         
       Set-AzureRmVMOperatingSystem        -Windows `
                                           -ComputerName $dc2name `
                                           -Credential $cred `
                                           -ProvisionVMAgent `
                                           -EnableAutoUpdate  |

       Set-AzureRmVMSourceImage            -PublisherName $publisher `
                                           -Offer $offer `
                                           -Skus $sku `
                                           -Version $version |


       Add-AzureRmVMDataDisk               -Name $dc2datadisk1.Name `
                                           -CreateOption Attach `
                                           -ManagedDiskId $dc2datadisk1.id `
                                           -Lun 0 |

       Add-AzureRmVMNetworkInterface       -Id $dc2nic.Id -Primary |

       Set-AzureRmVMBootDiagnostics        -Enable `
                                           -ResourceGroupName $resourcegroupname `
                                           -StorageAccountName $storagediag.StorageAccountName

       New-AzureRmVM                       -ResourceGroupName $resourceGroupName `
                                           -Location $location `
                                           -LicenseType "Windows_Server" `
                                           -VM $dc2vmConfig

write-Host -ForegroundColor Green $dc2name Complete
