#Windows Server Settings
$publisher = "MicrosoftWindowsServer"
$offer = "WindowsServer"
$sku = "2016-Datacenter"
$version = "latest"

#RDS Gateway Server Settings
$vm1vmsize = "Standard_DS11_v2"
$vm1osdiskSize = '128'
$vm1osdiskname = "VMNAME_OS_DISK" # Disk with VM name as prefix
$vm1vmname = "VMNAME" # VM Name
$vm1nicname = "VMNAME_NIC1" # VM NIC Name
$vm1ipaddress = "0.0.0.0" # VM internal IP address
$vm1pipName = "VMNAME_Public_IP"  # VM public IP address
$vm1domainlabel = ('dsgvm1'+(Get-Random))

#RD Session Server 1 settings
$vm2vmsize = "Standard_DS11_v2"
$vm2osdiskSize = '128'
$vm2osdiskname = "VMNAME_OS_DISK" # Disk with VM name as prefix
$vm2vmname = "VMNAME" # VM Name
$vm2nicname = "VMNAME_NIC1" # VM NIC Name
$vm2ipaddress = "0.0.0.0" # VM internal IP address

#RDS Session Server 2 settings
$vm3vmsize = "Standard_DS11_v2"
$vm3osdiskSize = '128'
$vm3osdiskname = "VMNAME_OS_DISK" # Disk with VM name as prefix
$vm3vmname = "VMNAME" # VM Name
$vm3nicname = "VMNAME_NIC1" # VM NIC Name
$vm3ipaddress = "0.0.0.0" # VM internal IP address

#General Configuration
$storagediagname = ('vm1diag'+(Get-Random))
$storagediagsku = "Standard_LRS"
$diskaccountType = "PremiumLRS"

#Resources
$resourceGroupName = "RESOURCEGROUP" # Resource group for VM
$location = "uk south"

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
$vnetrg = "RESOURCEGROUP" # RG of VNet
$subnetName = "Subnet_Data" # Subnet to attach VM to

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

# Create Resource Group for vm1
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

#Create public IP address for vm1 server
write-Host -ForegroundColor Cyan "Creating public IP address..."
$vm1pip =       New-AzureRmPublicIpAddress -Name $vm1pipName `
                -ResourceGroupName $resourceGroupName `
                -AllocationMethod Static `
                -DomainNameLabel $vm1domainlabel `
                -Location $location
write-Host -ForegroundColor Green "Public IP created"

#Create NSG for vm1 server to allow incoming HTTPS
write-Host -ForegroundColor Cyan "Creating network security group and rules..."
$vm1nsgrule =   New-AzureRmNetworkSecurityRuleConfig -Name "HTTPS_In" `
                -Description "Allow HTTPS inbound to vm1 server" `
                -Access Allow `
                -Protocol Tcp `
                -Direction Inbound `
                -Priority 101 `
                -SourceAddressPrefix Internet `
                -SourcePortRange * `
                -DestinationAddressPrefix * `
                -DestinationPortRange 443

$vm1nsg =       New-AzureRmNetworkSecurityGroup -ResourceGroupName $resourceGroupName `
                -Location $location `
                -Name "NSG_vm1_Server" `
                -SecurityRules $vm1nsgrule
write-Host -ForegroundColor Green "Network security group and rules created"

# Create new NICs in VNET
write-Host -ForegroundColor Cyan "Creating network interface..."
$vm1nic =       New-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName `
                -Name $vm1nicname `
                -SubnetID $subnetID `
                -Location $location `
                -PublicIpAddressId $vm1pip.Id `
                -PrivateIpAddress $vm1ipaddress `
                -NetworkSecurityGroupId $vm1nsg.Id

$vm2nic =    New-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName `
                -Name $vm2nicname `
                -SubnetID $subnetID `
                -Location $location `
                -PrivateIpAddress $vm2ipaddress

$vm3nic =    New-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName `
                -Name $vm3nicname `
                -SubnetID $subnetID `
                -Location $location `
                -PrivateIpAddress $vm3ipaddress

write-Host -ForegroundColor Green "Network interface created"

#Create managed data disks for vm1 server

#Disk 1 - 1023Gb for user profile storage remote apps
write-Host -ForegroundColor Cyan "Creating managed disk 1..."
$vm1datadisk1config =   New-AzureRmDiskConfig -Location $location `
                        -DiskSizeGB 1023 `
                        -AccountType $diskaccountType `
                        -OsType Windows `
                        -CreateOption Empty

$vm1datadisk1 =         New-AzureRmDisk -ResourceGroupName $resourceGroupName `
                        -DiskName ($vm1vmname+"_Data_Disk1") `
                        -Disk $vm1datadisk1config

write-Host -ForegroundColor Green "Managed disk 1 created"

#Disk 1 - 1023Gb for user profile storage remote desktop
write-Host -ForegroundColor Cyan "Creating managed disk 2..."
$vm1datadisk2config =   New-AzureRmDiskConfig    -Location $location `
                        -DiskSizeGB 1023 `
                        -AccountType $diskaccountType `
                        -OsType Windows `
                        -CreateOption Empty

$vm1datadisk2 =         New-AzureRmDisk -ResourceGroupName $resourceGroupName `
                        -DiskName ($vm1vmname+"_Data_Disk2") `
                        -Disk $vm1datadisk2config

write-Host -ForegroundColor Green "Managed disk 2 created"

#Create Storage Account for boot diagnostics
write-Host -ForegroundColor Cyan "Creating diagnostic storage account..."
$storagediag = New-AzureRmStorageAccount -Location $location -Name $storagediagname -ResourceGroupName $resourcegroupname -SkuName $storagediagsku
write-Host -ForegroundColor Green "Diagnostic storage created"

#Create RDS Server
write-Host -ForegroundColor Cyan Creating server $vm1vmname ...

$vm1vmConfig = New-AzureRmVMConfig              -VMName $vm1vmName `
                                                -VMSize $vm1vmsize |

               Set-AzureRmVMOperatingSystem     -Windows `
                                                -ComputerName $vm1vmName `
                                                -Credential $cred `
                                                -ProvisionVMAgent `
                                                -EnableAutoUpdate  |

                Set-AzureRmVMSourceImage        -PublisherName $publisher `
                                                -Offer $offer `
                                                -Skus $sku `
                                                -Version $version |

                Set-AzureRmVMOSDisk             -Name $vm1osdiskname `
                                                -DiskSizeInGB $vm1osdiskSize `
                                                -StorageAccountType $diskaccountType `
                                                -CreateOption fromImage `
                                                -Windows  |

                Add-AzureRmVMDataDisk           -Name $vm1datadisk1.Name `
                                                -CreateOption Attach `
                                                -ManagedDiskId $vm1datadisk1.id `
                                                -Lun 0 |

                Add-AzureRmVMDataDisk           -Name $vm1datadisk2.Name `
                                                -CreateOption Attach `
                                                -ManagedDiskId $vm1datadisk2.id `
                                                -Lun 1 |

                Add-AzureRmVMNetworkInterface   -Id $vm1nic.Id -Primary |

                Set-AzureRmVMBootDiagnostics    -Enable `
                                                -ResourceGroupName $resourcegroupname `
                                                -StorageAccountName $storagediag.StorageAccountName

                New-AzureRmVM                   -ResourceGroupName $resourceGroupName `
                                                -Location $location `
                                                -VM $vm1vmConfig

write-Host -ForegroundColor Green server $vm1vmname Complete

#Create RDS Session Host Server 1
write-Host -ForegroundColor Cyan Creating $vm2vmname ...

$vm2vmConfig = New-AzureRmVMConfig           -VMName $vm2vmName `
                                                -VMSize $vm2vmsize |

               Set-AzureRmVMOperatingSystem     -Windows `
                                                -ComputerName $vm2vmName `
                                                -Credential $cred `
                                                -ProvisionVMAgent `
                                                -EnableAutoUpdate  |

                Set-AzureRmVMSourceImage        -PublisherName $publisher `
                                                -Offer $offer `
                                                -Skus $sku `
                                                -Version $version |

                Set-AzureRmVMOSDisk             -Name $vm2osdiskname `
                                                -DiskSizeInGB $vm2osdiskSize `
                                                -StorageAccountType $diskaccountType `
                                                -CreateOption fromImage `
                                                -Windows  |

                Add-AzureRmVMNetworkInterface   -Id $vm2nic.Id -Primary |

                Set-AzureRmVMBootDiagnostics    -Enable `
                                                -ResourceGroupName $resourcegroupname `
                                                -StorageAccountName $storagediag.StorageAccountName

                New-AzureRmVM                   -ResourceGroupName $resourceGroupName `
                                                -Location $location `
                                                -VM $vm2vmConfig

write-Host -ForegroundColor Green server $vm2vmname Complete

#Create RDS Session Host Server 2
write-Host -ForegroundColor Cyan Creating $vm3vmname ...

$vm3vmConfig = New-AzureRmVMConfig           -VMName $vm3vmName `
                                                -VMSize $vm3vmsize |

               Set-AzureRmVMOperatingSystem     -Windows `
                                                -ComputerName $vm3vmName `
                                                -Credential $cred `
                                                -ProvisionVMAgent `
                                                -EnableAutoUpdate  |

                Set-AzureRmVMSourceImage        -PublisherName $publisher `
                                                -Offer $offer `
                                                -Skus $sku `
                                                -Version $version |

                Set-AzureRmVMOSDisk             -Name $vm3osdiskname `
                                                -DiskSizeInGB $vm3osdiskSize `
                                                -StorageAccountType $diskaccountType `
                                                -CreateOption fromImage `
                                                -Windows  |

                Add-AzureRmVMNetworkInterface   -Id $vm3nic.Id -Primary |

                Set-AzureRmVMBootDiagnostics    -Enable `
                                                -ResourceGroupName $resourcegroupname `
                                                -StorageAccountName $storagediag.StorageAccountName

                New-AzureRmVM                   -ResourceGroupName $resourceGroupName `
                                                -Location $location `
                                                -VM $vm3vmConfig

write-Host -ForegroundColor Green $vm3vmname Complete