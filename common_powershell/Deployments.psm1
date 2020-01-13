Import-Module $PSScriptRoot/Logging.psm1 -Force


# Create resource group if it does not exist
# ------------------------------------------
function Deploy-ResourceGroup {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of resource group to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that resource group '$Name' exists..."
    $resourceGroup = Get-AzResourceGroup -Name $Name -Location $Location -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating resource group '$Name'"
        $resourceGroup = New-AzResourceGroup -Name $Name -Location $Location -Force
        if ($?) {
            Add-LogMessage -Level Success "Created resource group '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create resource group '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "Resource group '$Name' already exists"
    }
    return $resourceGroup
}
Export-ModuleMember -Function Deploy-ResourceGroup


# Create virtual network if it does not exist
# ------------------------------------------
function Deploy-VirtualNetwork {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of virtual network to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Specifies a range of IP addresses for a virtual network")]
        $AddressPrefix,
        [Parameter(Position = 3, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that virtual network '$Name' exists..."
    $vnet = Get-AzVirtualNetwork -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating virtual network '$Name'"
        $vnet = New-AzVirtualNetwork -Name $Name -Location $Location -ResourceGroupName $ResourceGroupName -AddressPrefix "$AddressPrefix" -Force
        if ($?) {
            Add-LogMessage -Level Success "Created virtual network '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create virtual network '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "Virtual network '$Name' already exists"
    }
    return $vnet
}
Export-ModuleMember -Function Deploy-VirtualNetwork


# Create subnet if it does not exist
# ----------------------------------
function Deploy-Subnet {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of subnet to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Virtual network to deploy into")]
        $VirtualNetwork,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Specifies a range of IP addresses for a virtual network")]
        $AddressPrefix
    )
    Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
    Add-LogMessage -Level Info "Ensuring that subnet '$Name' exists..."
    $subnet = Get-AzVirtualNetworkSubnetConfig -Name $Name -VirtualNetwork $VirtualNetwork -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating subnet '$Name'"
        $subnet = Add-AzVirtualNetworkSubnetConfig -Name $Name -VirtualNetwork $VirtualNetwork -AddressPrefix $AddressPrefix
        $VirtualNetwork | Set-AzVirtualNetwork
        if ($?) {
            Add-LogMessage -Level Success "Created subnet '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create subnet '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "Subnet '$Name' already exists"
    }
    return $subnet
}
Export-ModuleMember -Function Deploy-Subnet


# Create a virtual machine NIC
# ----------------------------
function Deploy-VirtualMachineNIC {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of VM NIC to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Subnet to attach this NIC to")]
        $Subnet,
        [Parameter(Position = 3, Mandatory = $true, HelpMessage = "Private IP address for this NIC")]
        $PrivateIpAddress,
        [Parameter(Position = 4, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that VM network card '$Name' exists..."
    $vmNic = Get-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating VM network card '$Name'"
        $vmIpConfig = New-AzNetworkInterfaceIpConfig -Name "ipconfig-$Name" -Subnet $subnet -PrivateIpAddress $PrivateIpAddress -Primary
        $vmNic = New-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -IpConfiguration $vmIpConfig -Force
        if ($?) {
            Add-LogMessage -Level Success "Created VM network card '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create VM network card '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "VM network card '$Name' already exists"
    }
    return $vmNic
}
Export-ModuleMember -Function Deploy-VirtualMachineNIC


# Create a managed disk
# ---------------------
function Deploy-ManagedDisk {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of disk to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Disk size in GB")]
        $SizeGB,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Disk type (eg. Standard_LRS)")]
        $Type,
        [Parameter(Position = 3, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Position = 4, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that managed disk '$Name' exists..."
    $disk = Get-AzDisk -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating $SizeGB GB managed disk '$Name'"
        $diskConfig = New-AzDiskConfig -Location $Location -DiskSizeGB $SizeGB -AccountType $Type -OsType Linux -CreateOption Empty
        $disk = New-AzDisk -ResourceGroupName $ResourceGroupName -DiskName $Name -Disk $diskConfig
        if ($?) {
            Add-LogMessage -Level Success "Created managed disk '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create managed disk '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "Managed disk '$Name' already exists"
    }
    return $disk
}
Export-ModuleMember -Function Deploy-ManagedDisk


# Create network security group if it does not exist
# --------------------------------------------------
function Deploy-NetworkSecurityGroup {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of network security group to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that network security group '$Name' exists..."
    $nsg = Get-AzNetworkSecurityGroup -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating network security group '$Name'"
        $nsg = New-AzNetworkSecurityGroup  -Name $Name -Location $Location -ResourceGroupName $ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Created network security group '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create network security group '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "Network security group '$Name' already exists"
    }
    return $nsg
}
Export-ModuleMember -Function Deploy-NetworkSecurityGroup


# Create network security group rule if it does not exist
# -------------------------------------------------------
function Deploy-NetworkSecurityGroupRule {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of network security group rule to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of network security group to deploy into")]
        $NetworkSecurityGroup,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Description,
        [Parameter(Position = 3, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Priority,
        [Parameter(Position = 4, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Direction,
        [Parameter(Position = 5, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Access,
        [Parameter(Position = 6, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Protocol,
        [Parameter(Position = 7, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $SourceAddressPrefix,
        [Parameter(Position = 8, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $SourcePortRange,
        [Parameter(Position = 9, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $DestinationAddressPrefix,
        [Parameter(Position = 10, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $DestinationPortRange
    )
    Add-LogMessage -Level Info "Ensuring that NSG rule '$Name' exists..."
    $_ = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating NSG rule '$Name'"
        $_ = Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup `
                                             -Name "$Name" `
                                             -Description "$Description" `
                                             -Priority $Priority `
                                             -Direction $Direction -Access $Access -Protocol "$Protocol" `
                                             -SourceAddressPrefix "$SourceAddressPrefix" -SourcePortRange $SourcePortRange `
                                             -DestinationAddressPrefix "$DestinationAddressPrefix" -DestinationPortRange $DestinationPortRange | Set-AzNetworkSecurityGroup
        if ($?) {
            Add-LogMessage -Level Success "Created NSG rule '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create NSG rule '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "Updating NSG rule '$Name'"
        $_ = Set-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup `
                                             -Name "$Name" `
                                             -Description "$Description" `
                                             -Priority $Priority `
                                             -Direction $Direction -Access $Access -Protocol "$Protocol" `
                                             -SourceAddressPrefix "$SourceAddressPrefix" -SourcePortRange $SourcePortRange `
                                             -DestinationAddressPrefix "$DestinationAddressPrefix" -DestinationPortRange $DestinationPortRange | Set-AzNetworkSecurityGroup
    }
}
Export-ModuleMember -Function Deploy-NetworkSecurityGroupRule


# Create storage account if it does not exist
# ------------------------------------------
function Deploy-StorageAccount {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of storage account to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that storage account '$Name' exists..."
    $storageAccount = Get-AzStorageAccount -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating storage account '$Name'"
        $storageAccount = New-AzStorageAccount -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -SkuName "Standard_LRS" -Kind "StorageV2"
        if ($?) {
            Add-LogMessage -Level Success "Created storage account '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create storage account '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "Storage account '$Name' already exists"
    }
    return $storageAccount
}
Export-ModuleMember -Function Deploy-StorageAccount


# Create storage container if it does not exist
# ------------------------------------------
function Deploy-StorageContainer {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of storage container to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of storage account to deploy into")]
        $StorageAccount
    )
    Add-LogMessage -Level Info "Ensuring that storage container '$Name' exists..."
    $storageContainer = Get-AzStorageContainer -Name $Name -Context $StorageAccount.Context -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating storage container '$Name' in storage account '$($StorageAccount.StorageAccountName)'"
        $storageContainer = New-AzStorageContainer -Name $Name -Context $StorageAccount.Context
        if ($?) {
            Add-LogMessage -Level Success "Created storage container"
        } else {
            Add-LogMessage -Level Failure "Failed to create storage container!"
            throw "Failed to create storage container '$Name' in storage account '$($StorageAccount.StorageAccountName)'!"
        }
    } else {
        Add-LogMessage -Level Success "Storage container '$Name' already exists in storage account '$($StorageAccount.StorageAccountName)'"
    }
    return $storageContainer
}
Export-ModuleMember -Function Deploy-StorageContainer


# Deploy an ARM template and log the output
# -----------------------------------------
function Deploy-ArmTemplate {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Path to template file")]
        $TemplatePath,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Template parameters")]
        $Params,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName
    )
    $templateName = Split-Path -Path "$TemplatePath" -LeafBase
    New-AzResourceGroupDeployment -ResourceGroupName $ResourceGroupName -TemplateFile $TemplatePath @params -Verbose -DeploymentDebugLogLevel ResponseContent
    $result = $?
    Add-DeploymentLogMessages -ResourceGroupName $ResourceGroupName -DeploymentName $templateName
    if ($result) {
        Add-LogMessage -Level Success "Template deployment '$templateName' succeeded"
    } else {
        Add-LogMessage -Level Failure "Template deployment '$templateName' failed!"
        throw "Template deployment has failed for '$templateName'. Please check the error message above before re-running this script."
    }
}
Export-ModuleMember -Function Deploy-ArmTemplate


# Run remote Powershell script
# ----------------------------
function Invoke-LoggedRemotePowershell {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Path to remote script")]
        $ScriptPath,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of VM to run on")]
        $VMName,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Name of resource group VM belongs to")]
        $ResourceGroupName,
        [Parameter(Position = 3, Mandatory = $false, HelpMessage = "(Optional) script parameters")]
        $Parameter = $null
    )
    if ($Parameter -eq $null) {
        $result = Invoke-AzVMRunCommand -Name $VMName -ResourceGroupName $ResourceGroupName -CommandId 'RunPowerShellScript' -ScriptPath $ScriptPath
        $success = $?
    } else {
        $result = Invoke-AzVMRunCommand -Name $VMName -ResourceGroupName $ResourceGroupName -CommandId 'RunPowerShellScript' -ScriptPath $ScriptPath -Parameter $Parameter
        $success = $?
    }
    Write-Output $result.Value
    $stdoutCode = ($result.Value[0].Code -split "/")[-1]
    $stderrCode = ($result.Value[1].Code -split "/")[-1]
    if ($success -and ($stdoutCode -eq "succeeded") -and ($stderrCode -eq "succeeded")) {
        Add-LogMessage -Level Success "Remote script execution succeeded"
    } else {
        Add-LogMessage -Level Failure "Remote script execution failed!"
        throw "Remote script execution has failed. Please check the error message above before re-running this script."
    }
}
Export-ModuleMember -Function Invoke-LoggedRemotePowershell


# Create Linux virtual machine if it does not exist
# -------------------------------------------------
function Deploy-UbuntuVirtualMachine {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of virtual machine to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Size of virtual machine to deploy")]
        $Size,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Disk type (eg. Standard_LRS)")]
        $OsDiskType,
        [Parameter(Position = 3, Mandatory = $true, HelpMessage = "ID of VM image to deploy")]
        $CloudInitYaml,
        [Parameter(Position = 4, Mandatory = $true, HelpMessage = "Administrator username")]
        $AdminUsername,
        [Parameter(Position = 5, Mandatory = $true, HelpMessage = "Administrator password")]
        $AdminPassword,
        [Parameter(Position = 6, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $NicId,
        [Parameter(Position = 7, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Position = 8, Mandatory = $true, HelpMessage = "Name of storage account for boot diagnostics")]
        $BootDiagnosticsAccount,
        [Parameter(Position = 9, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location,
        [Parameter(Position = 10, HelpMessage = "ID of VM image to deploy")]
        $ImageId = $null,
        [Parameter(Position = 11, HelpMessage = "IDs of data disks")]
        $DataDiskIds = $null
    )
    Add-LogMessage -Level Info "Ensuring that virtual machine '$Name' exists..."
    $vm = Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Write-Host "Name: $Name"
        Write-Host "Size: $Size"
        Write-Host "OsDiskType: $OsDiskType"
        Write-Host "ImageId: $ImageId"
        Write-Host "CloudInitYaml: $CloudInitYaml"
        Write-Host "NicId: $NicId"
        Write-Host "ResourceGroupName: $ResourceGroupName"
        Write-Host "BootDiagnosticsAccount: $BootDiagnosticsAccount"
        Write-Host "AdminUsername: $AdminUsername"
        Write-Host "AdminPassword: $AdminPassword"
        Write-Host "Location: $Location"
        Write-Host "DataDiskIds: $DataDiskIds"
        $adminCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AdminUsername, (ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force)
        # Build VM configuration
        $vmConfig = New-AzVMConfig -VMName $Name -VMSize $Size
        # Set source image to a custom image or to latest Ubuntu (default)
        if ($ImageId) {
            $vmConfig = Set-AzVMSourceImage -VM $vmConfig -Id $ImageId
        } else {
            Set-AzVMSourceImage -VM $vmConfig -PublisherName Canonical -Offer UbuntuServer -Skus 18.04-LTS -Version "latest"
        }
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $Name -Credential $adminCredentials -CustomData $CloudInitYaml
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $NicId -Primary
        $vmConfig = Set-AzVMOSDisk -VM $vmConfig -StorageAccountType $OsDiskType -Name "$Name-OS-DISK" -CreateOption FromImage
        $vmConfig = Set-AzVMBootDiagnostic -VM $vmConfig -Enable -ResourceGroupName $BootDiagnosticsAccount.ResourceGroupName -StorageAccountName $BootDiagnosticsAccount.StorageAccountName
        # Add optional data disks
        $lun = 0
        foreach ($diskId in $DataDiskIds) {
            $lun += 1
            $vmConfig = Add-AzVMDataDisk -VM $vmConfig -ManagedDiskId $diskId -CreateOption Attach -Lun $lun
        }
        Add-LogMessage -Level Info "[ ] Creating virtual machine '$Name'"
        $vm = New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig
        if ($?) {
            Add-LogMessage -Level Success "Created virtual machine '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create virtual machine '$Name'!"
        }
    } else {
        Add-LogMessage -Level Success "Virtual machine '$Name' already exists"
    }
    return $vm
}
Export-ModuleMember -Function Deploy-UbuntuVirtualMachine