#Before starting enable the Marketplace images for Data Science and GIT hub to be deployed programmatically.
#
#JUPYTER DS VM Settings
$dspublisher = "microsoft-ads"
$dsoffer = "linux-data-science-vm-ubuntu"
$dssku = "linuxdsvmubuntu"
$dsversion = "latest"
$dsvmsize = "Standard_NC6"
$dsosdiskSize = '100'
$dsosdiskname = "VMNAME_OS_DISK" # Disk with VM name as prefix
$dsvmname = "VMNAME" # VM name
$dsnicname = "VM_NIC1" # VM NIC Name
$dsipaddress = "0.0.0.0" # Private IP address
$dsdiskaccountType = "StandardLRS"


#GIT VM Settings
$gitpublisher = "gitlab"
$gitoffer = "gitlab-ce"
$gitsku = "gitlab-ce"
$gitversion = "latest"
$gitvmsize = "Standard_DS2_v2"
$gitosdiskSize = '100'
$gitosdiskname = "VMNAME_OS_DISK"
$gitvmname = "VMNAME" # VM name
$gitnicname = "VMNAME_NIC1" # VM NIC Name
$gitipaddress = "0.0.0.0" # Private IP address
$gitdiskaccountType = "PremiumLRS"
$gitdatadiskaccountType = "PremiumLRS"

#HackMD VM Settings
$hackmdpublisher = "Canonical"
$hackmdoffer = "UbuntuServer"
$hackmdsku = "16.04-LTS"
$hackmdversion = "latest"
$hackmdvmsize = "Standard_DS2_v2"
$hackmdosdiskSize = '750'
$hackmdosdiskname = "VMNAME_OS_DISK"
$hackmdvmname = "VMNAME" # VM name
$hackmdnicname = "VMNAME_NIC1" # VM NIC Name
$hackmdipaddress = "0.0.0.0" # Private IP address
$hackmddiskaccountType = "PremiumLRS"

#Diagnostic Storage
$storagediagname = ('linuxdiag'+(Get-Random))
$storagediagsku = "Standard_LRS"

#Resources
$resourceGroupName = "RESOURCEGROUP" # Resource group name for VMs
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
$vnetrg = "RESOURCEGROUP" # Resource group of VNet
$subnetName = "Subnet_Data" # Subnet VM to be installed to

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

# Create Resource Group for Linux Server
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

# Create new NIC in VNET
write-Host -ForegroundColor Cyan "Creating network interface..."
$dsnic =    New-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName `
            -Name $dsnicname `
            -SubnetID $subnetID `
            -Location $location `
            -PrivateIpAddress $dsipaddress

$gitnic =   New-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName `
            -Name $gitnicname `
            -SubnetID $subnetID `
            -Location $location `
            -PrivateIpAddress $gitipaddress

$hackmdnic = New-AzureRmNetworkInterface -ResourceGroupName $resourceGroupName `
            -Name $hackmdnicname `
            -SubnetID $subnetID `
            -Location $location `
            -PrivateIpAddress $hackmdipaddress

write-Host -ForegroundColor Green "Network interface created"

#Create Storage Account for boot diagnostics
write-Host -ForegroundColor Cyan "Creating diagnostic storage account..."
$storagediag = New-AzureRmStorageAccount -Location $location -Name $storagediagname -ResourceGroupName $resourcegroupname -SkuName $storagediagsku
write-Host -ForegroundColor Green "Diagnostic storage created"

#Data Disk - GIT LAB
write-Host -ForegroundColor Cyan "Creating managed disk for GIT LAB..."
$gitdatadiskconfig = New-AzureRmDiskConfig   -Location $location `
                                             -DiskSizeGB 750 `
                                             -AccountType $gitdatadiskaccountType `
                                             -OsType Linux `
                                             -CreateOption Empty

$gitdatadisk = New-AzureRmDisk  -ResourceGroupName $resourceGroupName `
                                -DiskName ($gitvmname+"_Data_Disk1") `
                                -Disk $gitdatadiskconfig
write-Host -ForegroundColor Green "Managed disk for GITLAB created"


#Create DS VM Server
write-Host -ForegroundColor Cyan Creating $dsvmname ...

$dsvmConfig = New-AzureRmVMConfig          -VMName $dsvmName `
                                           -VMSize $dsvmsize |

       Set-AzureRmVMPlan                   -Name $dssku `
                                           -Publisher $dspublisher `
                                           -Product $dsoffer |
       
       Set-AzureRmVMOperatingSystem        -Linux `
                                           -ComputerName $dsvmName `
                                           -Credential $cred |

       Set-AzureRmVMSourceImage            -PublisherName $dspublisher `
                                           -Offer $dsoffer `
                                           -Skus $dssku `
                                           -Version $dsversion |

       Set-AzureRmVMOSDisk                 -Name $dsosdiskname `
                                           -DiskSizeInGB $dsosdiskSize `
                                           -StorageAccountType $dsdiskaccountType `
                                           -CreateOption fromImage `
                                           -Linux  |

       Add-AzureRmVMNetworkInterface       -Id $dsnic.Id -Primary |

       Set-AzureRmVMBootDiagnostics        -Enable `
                                           -ResourceGroupName $resourcegroupname `
                                           -StorageAccountName $storagediag.StorageAccountName

       New-AzureRmVM                       -ResourceGroupName $resourceGroupName `
                                           -Location $location `
                                           -VM $dsvmConfig

write-Host -ForegroundColor Green $dsvmname Complete

#Create GIT Server
write-Host -ForegroundColor Cyan Creating $gitvmname ...

$gitvmConfig = New-AzureRmVMConfig         -VMName $gitvmName `
                                           -VMSize $gitvmsize |

       Set-AzureRmVMPlan                   -Name $gitsku `
                                           -Publisher $gitpublisher `
                                           -Product $gitoffer |

       Set-AzureRmVMOperatingSystem        -Linux `
                                           -ComputerName $gitvmName `
                                           -Credential $cred |

       Set-AzureRmVMSourceImage            -PublisherName $gitpublisher `
                                           -Offer $gitoffer `
                                           -Skus $gitsku `
                                           -Version $gitversion |

       Set-AzureRmVMOSDisk                 -Name $gitosdiskname `
                                           -DiskSizeInGB $gitosdiskSize `
                                           -StorageAccountType $gitdiskaccountType `
                                           -CreateOption fromImage `
                                           -Linux  |

       Add-AzureRmVMDataDisk               -Name $gitdatadisk.Name `
                                           -CreateOption Attach `
                                           -ManagedDiskId $gitdatadisk.id `
                                           -Lun 0 |

       Add-AzureRmVMNetworkInterface       -Id $gitnic.Id -Primary |

       Set-AzureRmVMBootDiagnostics        -Enable `
                                           -ResourceGroupName $resourcegroupname `
                                           -StorageAccountName $storagediag.StorageAccountName

       New-AzureRmVM                       -ResourceGroupName $resourceGroupName `
                                           -Location $location `
                                           -VM $gitvmConfig

write-Host -ForegroundColor Green $gitvmname Complete

# Create HackMD Server
write-Host -ForegroundColor Cyan Creating $hackmdvmname ...
$hackmdvmConfig = New-AzureRmVMConfig      -VMName $hackmdvmName `
                                           -VMSize $hackmdvmsize |

       Set-AzureRmVMOperatingSystem        -Linux `
                                           -ComputerName $hackmdvmName `
                                           -Credential $cred |

       Set-AzureRmVMSourceImage            -PublisherName $hackmdpublisher `
                                           -Offer $hackmdoffer `
                                           -Skus $hackmdsku `
                                           -Version $hackmdversion  |

       Set-AzureRmVMOSDisk                 -Name $hackmdosdiskname `
                                           -DiskSizeInGB $hackmdosdiskSize `
                                           -StorageAccountType $hackmddiskaccountType `
                                           -CreateOption fromImage `
                                           -Linux  |

       Add-AzureRmVMNetworkInterface       -Id $hackmdnic.Id -Primary |

       Set-AzureRmVMBootDiagnostics        -Enable `
                                           -ResourceGroupName $resourcegroupname `
                                           -StorageAccountName $storagediag.StorageAccountName

       New-AzureRmVM                       -ResourceGroupName $resourceGroupName `
                                           -Location $location `
                                           -VM $hackmdvmConfig

write-Host -ForegroundColor Green $hackmdvmname Complete