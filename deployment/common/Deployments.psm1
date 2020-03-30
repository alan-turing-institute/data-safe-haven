Import-Module Az
Import-Module $PSScriptRoot/Logging.psm1 -Force


# Create network security group rule if it does not exist
# -------------------------------------------------------
function Add-NetworkSecurityGroupRule {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of network security group rule to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "A NetworkSecurityGroup object to apply this rule to")]
        $NetworkSecurityGroup,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "A description of the network security rule")]
        $Description,
        [Parameter(Position = 3, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Priority,
        [Parameter(Position = 4, Mandatory = $true, HelpMessage = "Whether to apply to incoming or outgoing traffic")]
        $Direction,
        [Parameter(Position = 5, Mandatory = $true, HelpMessage = "Whether network traffic is allowed or denied")]
        $Access,
        [Parameter(Position = 6, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Protocol,
        [Parameter(Position = 7, Mandatory = $true, HelpMessage = "Source addresses. One or more of: a CIDR, an IP address range, a wildcard or an Azure tag (eg. VirtualNetwork)")]
        $SourceAddressPrefix,
        [Parameter(Position = 8, Mandatory = $true, HelpMessage = "Source port or range. One or more of: an integer, a range of integers or a wildcard")]
        $SourcePortRange,
        [Parameter(Position = 9, Mandatory = $true, HelpMessage = "Destination addresses. One or more of: a CIDR, an IP address range, a wildcard or an Azure tag (eg. VirtualNetwork)")]
        $DestinationAddressPrefix,
        [Parameter(Position = 10, Mandatory = $true, HelpMessage = "Destination port or range. One or more of: an integer, a range of integers or a wildcard")]
        $DestinationPortRange,
        [Parameter(Position = 11, Mandatory = $false, HelpMessage = "Print verbose logging messages")]
        [switch]$VerboseLogging = $false
    )
    if ($VerboseLogging) { Add-LogMessage -Level Info "Ensuring that NSG rule '$Name' exists on '$($NetworkSecurityGroup.Name)'..." }
    $_ = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        if ($VerboseLogging) { Add-LogMessage -Level Info "[ ] Creating NSG rule '$Name'" }
        $_ = Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup `
                                             -Name "$Name" `
                                             -Description "$Description" `
                                             -Priority $Priority `
                                             -Direction "$Direction" `
                                             -Access "$Access" `
                                             -Protocol "$Protocol" `
                                             -SourceAddressPrefix $SourceAddressPrefix `
                                             -SourcePortRange $SourcePortRange `
                                             -DestinationAddressPrefix $DestinationAddressPrefix `
                                             -DestinationPortRange $DestinationPortRange | Set-AzNetworkSecurityGroup
        if ($?) {
            if ($VerboseLogging) { Add-LogMessage -Level Success "Created NSG rule '$Name'" }
        } else {
            if ($VerboseLogging) { Add-LogMessage -Level Fatal "Failed to create NSG rule '$Name'!" }
        }
    } else {
        if ($VerboseLogging) { Add-LogMessage -Level InfoSuccess "Updating NSG rule '$Name'" }
        $_ = Set-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup `
                                             -Name "$Name" `
                                             -Description "$Description" `
                                             -Priority $Priority `
                                             -Direction "$Direction" -Access "$Access" -Protocol "$Protocol" `
                                             -SourceAddressPrefix $SourceAddressPrefix -SourcePortRange $SourcePortRange `
                                             -DestinationAddressPrefix $DestinationAddressPrefix -DestinationPortRange $DestinationPortRange | Set-AzNetworkSecurityGroup
    }
}
Export-ModuleMember -Function Add-NetworkSecurityGroupRule


# Associate a VM to an NSG
# ------------------------
function Add-VmToNSG {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of virtual machine")]
        $VMName,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of network security group")]
        $NSGName
    )
    Add-LogMessage -Level Info ("[ ] Associating $VMName with $NSGName...")
    $nic = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq (Get-AzVM -Name $VMName).Id }
    $nsg = Get-AzNetworkSecurityGroup | Where-Object { $_.Name -eq $NSGName }
    $nic.NetworkSecurityGroup = $nsg
    $_ = ($nic | Set-AzNetworkInterface)
    if ($?) {
        Add-LogMessage -Level Success "NSG association succeeded"
    } else {
        Add-LogMessage -Level Fatal "NSG association failed!"
    }
}
Export-ModuleMember -Function Add-VmToNSG


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
    New-AzResourceGroupDeployment -Name $templateName -ResourceGroupName $ResourceGroupName -TemplateFile $TemplatePath @Params -Verbose -DeploymentDebugLogLevel ResponseContent -ErrorVariable azErr
    $result = $?
    Add-DeploymentLogMessages -ResourceGroupName $ResourceGroupName -DeploymentName $templateName
    if ($azErr) {
        foreach ( $errMsg in $azErr[0..2] ) {
            Add-LogMessage -Level Failure "$errMsg"
        }
    }
    if ($result) {
        Add-LogMessage -Level Success "Template deployment '$templateName' succeeded"
    } else {
        Add-LogMessage -Level Failure "Template deployment '$templateName' failed!"
        throw "Template deployment has failed for '$templateName'. Please check the error message above before re-running this script."
    }
}
Export-ModuleMember -Function Deploy-ArmTemplate


# Create a key vault if it does not exist
# ---------------------------------------
function Deploy-KeyVault {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of disk to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location
    )
    Add-LogMessage -Level Info "Ensuring that key vault '$Name' exists..."
    $keyVault = Get-AzKeyVault -VaultName $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($null -eq $keyVault) {
        Add-LogMessage -Level Info "[ ] Creating key vault '$Name'"
        $keyVault = New-AzKeyVault -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location
        if ($?) {
            Add-LogMessage -Level Success "Created key vault '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create key vault '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Key vault '$Name' already exists"
    }
    return $keyVault
}
Export-ModuleMember -Function Deploy-KeyVault


# Create a managed disk if it does not exist
# ------------------------------------------
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
        Add-LogMessage -Level InfoSuccess "Managed disk '$Name' already exists"
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
        Add-LogMessage -Level InfoSuccess "Network security group '$Name' already exists"
    }
    return $nsg
}
Export-ModuleMember -Function Deploy-NetworkSecurityGroup


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
        Add-LogMessage -Level InfoSuccess "Resource group '$Name' already exists"
    }
    return $resourceGroup
}
Export-ModuleMember -Function Deploy-ResourceGroup


# Create subnet if it does not exist
# ----------------------------------
function Deploy-Subnet {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of subnet to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "A VirtualNetwork object to deploy into")]
        $VirtualNetwork,
        [Parameter(Position = 2, Mandatory = $true, HelpMessage = "Specifies a range of IP addresses for a virtual network")]
        $AddressPrefix
    )
    Set-Item Env:\SuppressAzurePowerShellBreakingChangeWarnings "true"
    Add-LogMessage -Level Info "Ensuring that subnet '$Name' exists..."
    $_ = Get-AzVirtualNetworkSubnetConfig -Name $Name -VirtualNetwork $VirtualNetwork -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating subnet '$Name'"
        Add-AzVirtualNetworkSubnetConfig -Name $Name -VirtualNetwork $VirtualNetwork -AddressPrefix $AddressPrefix
        $VirtualNetwork | Set-AzVirtualNetwork
        if ($?) {
            Add-LogMessage -Level Success "Created subnet '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create subnet '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Subnet '$Name' already exists"
    }
    return Get-AzSubnet -Name $Name -VirtualNetwork $VirtualNetwork
}
Export-ModuleMember -Function Deploy-Subnet


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
    Add-LogMessage -Level Info "Ensuring that storage account '$Name' exists in '$ResourceGroupName'..."
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
        Add-LogMessage -Level InfoSuccess "Storage account '$Name' already exists"
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
        Add-LogMessage -Level InfoSuccess "Storage container '$Name' already exists in storage account '$($StorageAccount.StorageAccountName)'"
    }
    return $storageContainer
}
Export-ModuleMember -Function Deploy-StorageContainer


# Create Linux virtual machine if it does not exist
# -------------------------------------------------
function Deploy-UbuntuVirtualMachine {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual machine to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Size of virtual machine to deploy")]
        $Size,
        [Parameter(Mandatory = $true, HelpMessage = "Administrator password")]
        $AdminPassword,
        [Parameter(Mandatory = $true, HelpMessage = "Administrator username")]
        $AdminUsername,
        [Parameter(Mandatory = $true, HelpMessage = "Name of storage account for boot diagnostics")]
        $BootDiagnosticsAccount,
        [Parameter(Mandatory = $true, HelpMessage = "ID of VM image to deploy")]
        $CloudInitYaml,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $NicId,
        [Parameter(Mandatory = $true, HelpMessage = "OS disk type (eg. Standard_LRS)")]
        $OsDiskType,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, ParameterSetName="ByImageId", HelpMessage = "ID of VM image to deploy")]
        $ImageId = $null,
        [Parameter(Mandatory = $true, ParameterSetName="ByImageSku", HelpMessage = "ID of VM image to deploy")]
        $ImageSku = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Size of OS disk (GB)")]
        $OsDiskSizeGb = $null,
        [Parameter(Mandatory = $false, HelpMessage = "IDs of data disks")]
        $DataDiskIds = $null
    )
    Add-LogMessage -Level Info "Ensuring that virtual machine '$Name' exists..."
    $vm = Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        $adminCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $AdminUsername, (ConvertTo-SecureString -String $AdminPassword -AsPlainText -Force)
        # Build VM configuration
        $vmConfig = New-AzVMConfig -VMName $Name -VMSize $Size
        # Set source image to a custom image or to latest Ubuntu (default)
        if ($ImageId) {
            $vmConfig = Set-AzVMSourceImage -VM $vmConfig -Id $ImageId
        } else {
            # $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName Canonical -Offer UbuntuServer -Skus 18.04-LTS -Version "latest"
            $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName Canonical -Offer UbuntuServer -Skus $ImageSku -Version "latest"
        }
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $Name -Credential $adminCredentials -CustomData $CloudInitYaml
        $vmConfig = Add-AzVMNetworkInterface -VM $vmConfig -Id $NicId -Primary
        if ($OsDiskSizeGb) {
            $vmConfig = Set-AzVMOSDisk -VM $vmConfig -StorageAccountType $OsDiskType -Name "$Name-OS-DISK" -CreateOption FromImage -DiskSizeInGB $OsDiskSizeGb
        } else {
            $vmConfig = Set-AzVMOSDisk -VM $vmConfig -StorageAccountType $OsDiskType -Name "$Name-OS-DISK" -CreateOption FromImage
        }
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
        Add-LogMessage -Level InfoSuccess "Virtual machine '$Name' already exists"
    }
    return $vm
}
Export-ModuleMember -Function Deploy-UbuntuVirtualMachine


# Create a virtual machine NIC
# ----------------------------
function Deploy-VirtualMachineNIC {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM NIC to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to attach this NIC to")]
        $Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        $Location,
        [Parameter(Mandatory = $false, HelpMessage = "Public IP address for this NIC")]
        [ValidateSet("Dynamic", "Static")]
        $PublicIpAddressAllocation = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Private IP address for this NIC")]
        $PrivateIpAddress = $null
    )
    Add-LogMessage -Level Info "Ensuring that VM network card '$Name' exists..."
    $vmNic = Get-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating VM network card '$Name'"
        $ipAddressParams = @{}
        if ($PublicIpAddressAllocation) {
            $PublicIpAddress = New-AzPublicIpAddress -Name "$Name-PIP" -ResourceGroupName $ResourceGroupName -AllocationMethod $PublicIpAddressAllocation -Location $Location
            $ipAddressParams["PublicIpAddress"] = $PublicIpAddress
        }
        if ($PrivateIpAddress) { $ipAddressParams["PrivateIpAddress"] = $PrivateIpAddress }
        # $vmNic = New-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -Subnet $Subnet -PrivateIpAddress $PrivateIpAddress -IpConfigurationName "ipconfig-$Name" -Force
        $vmNic = New-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -Subnet $Subnet -IpConfigurationName "ipconfig-$Name" -Location $Location @ipAddressParams -Force
        if ($?) {
            Add-LogMessage -Level Success "Created VM network card '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create VM network card '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "VM network card '$Name' already exists"
    }
    return $vmNic
}
Export-ModuleMember -Function Deploy-VirtualMachineNIC


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
        Add-LogMessage -Level InfoSuccess "Virtual network '$Name' already exists"
    }
    return $vnet
}
Export-ModuleMember -Function Deploy-VirtualNetwork


# Ensure that an Azure VM is turned on
# ------------------------------------
function Enable-AzVM {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of VM to enable")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        $ResourceGroupName
    )
    Add-LogMessage -Level Info "[ ] Ensuring that '$Name' is running"
    $powerState = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status).Statuses.Code[1]
    if ($powerState -eq "PowerState/running") {
        $_ = Restart-AzVM -Name $Name -ResourceGroupName $ResourceGroupName
        $success = $?
    } else {
        $_ = Start-AzVM -Name $Name -ResourceGroupName $ResourceGroupName
        $success = $?
    }
    $powerState = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status).Statuses.Code[1]
    if ($success) {
        Add-LogMessage -Level Success "Successfully (re)started '$Name' [$powerstate]"
    } else {
        Add-LogMessage -Level Fatal "Failed to (re)start '$Name' [$powerstate]!"
    }
}
Export-ModuleMember -Function Enable-AzVM


# Create subnet if it does not exist
# ----------------------------------
function Get-AzSubnet {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of subnet to deploy")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Virtual network to deploy into")]
        $VirtualNetwork
    )
    return ($VirtualNetwork.Subnets | Where-Object { $_.Name -eq $Name })[0]
}
Export-ModuleMember -Function Get-AzSubnet


# Run remote shell script
# -----------------------
function Invoke-RemoteScript {
    param(
        [Parameter(Mandatory = $true, ParameterSetName="ByPath", HelpMessage = "Path to local script that will be run locally")]
        $ScriptPath,
        [Parameter(Mandatory = $true, ParameterSetName="ByString", HelpMessage = "Name of VM to run on")]
        $Script,
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to run on")]
        $VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group VM belongs to")]
        $ResourceGroupName,
        [Parameter(Mandatory = $false, HelpMessage = "Type of script to run")]
        [ValidateSet("PowerShell", "UnixShell")]
        $Shell = "PowerShell",
        [Parameter(Mandatory = $false, HelpMessage = "(Optional) script parameters")]
        $Parameter = $null
    )
    # If we're given a script then create a file from it
    $tmpScriptFile = $null
    if ($Script) {
        $tmpScriptFile = New-TemporaryFile
        $Script | Out-File -FilePath $tmpScriptFile.FullName
        $ScriptPath = $tmpScriptFile.FullName
    }
    # Setup the remote command
    if ($Shell -eq "PowerShell") {
        $commandId = "RunPowerShellScript"
    } else {
        $commandId = "RunShellScript"
    }
    # Run the remote command
    if ($Parameter) {
        $result = Invoke-AzVMRunCommand -Name $VMName -ResourceGroupName $ResourceGroupName -CommandId $commandId -ScriptPath $ScriptPath -Parameter $Parameter
        $success = $?
    } else {
        $result = Invoke-AzVMRunCommand -Name $VMName -ResourceGroupName $ResourceGroupName -CommandId $commandId -ScriptPath $ScriptPath
        $success = $?
    }
    $success = $success -and ($result.Status -eq "Succeeded")
    foreach ($outputStream in $result.Value) {
        # Check for 'ComponentStatus/<stream name>/succeeded' as a signal of success
        $success = $success -and (($outputStream.Code -split "/")[-1] -eq "succeeded")
        # Check for '[x]' in the output stream as a signal of failure
        if ($outputStream.Message -ne "") {
            $success = $success -and ([string]($outputStream.Message) -NotLike '* `[x`] *')
        }
    }
    # Clean up any temporary scripts
    if ($tmpScriptFile) { Remove-Item $tmpScriptFile.FullName }
    # Check for success or failure
    if ($success) {
        Add-LogMessage -Level Success "Remote script execution succeeded"
    } else {
        Add-LogMessage -Level Failure "Remote script execution failed!"
        Add-LogMessage -Level Failure "Script output:`n$($result | Out-String)"
        throw "Remote script execution has failed. Please check the error message above before re-running this script."
    }
    return $result
}
Export-ModuleMember -Function Invoke-RemoteScript


# Update and reboot a machine
# ---------------------------
function Invoke-WindowsConfigureAndUpdate {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to run on")]
        $VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Path to common_powershell directory")]
        $CommonPowershellPath
    )
    # Install Powershell modules
    Add-LogMessage -Level Info "[ ] Installing required Powershell modules on '$VMName'"
    $powershellScriptPath = Join-Path $CommonPowershellPath "remote" "Install_Powershell_Modules.ps1"
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $powershellScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName
    Write-Output $result.Value
    # Set locale and run update script
    Add-LogMessage -Level Info "[ ] Setting OS locale and installing updates on '$VMName'"
    $InstallationScriptPath = Join-Path $CommonPowershellPath "remote" "Configure_Windows.ps1"
    $result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $InstallationScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName
    Write-Output $result.Value
    # Reboot the VM
    Add-LogMessage -Level Info "[ ] Rebooting VM '$VMName'"
    # $_ = Restart-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName
    # # The following syntax is preferred in future, but does not yet work
    # # $vmID = (Get-AzVM -ResourceGroupName $config.sre.rds.gateway.vmName -Name $config.sre.rds.rg).Id
    # # Restart-AzVM -Id $vmID
    # if ($?) {
    #     Add-LogMessage -Level Success "Rebooting VM '$VMName' succeeded"
    # } else {
    #     Add-LogMessage -Level Fatal "Rebooting VM '$VMName' failed!"
    # }
    Enable-AzVM -Name $VMName -ResourceGroupName $ResourceGroupName
}
Export-ModuleMember -Function Invoke-WindowsConfigureAndUpdate


# Remove Virtual Machine
# ----------------------
function Remove-VirtualMachine {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of the VM to remove")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of resource group containing the VM")]
        $ResourceGroupName
    )

    $_ = Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level InfoSuccess "VM '$Name' does not exist"
    } else {
        Add-LogMessage -Level Info "[ ] Removing VM '$Name'"
        $_ = Remove-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Removed VM '$Name'"
        } else {
            Add-LogMessage -Level Failure "Failed to remove VM '$Name'"
        }
    }
}
Export-ModuleMember -Function Remove-VirtualMachine


# Remove Virtual Machine disk
# ---------------------------
function Remove-VirtualMachineDisk {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of the disk to remove")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of resource group containing the disk")]
        $ResourceGroupName
    )

    $_ = Get-AzDisk -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level InfoSuccess "Disk '$Name' does not exist"
    } else {
        Add-LogMessage -Level Info "[ ] Removing disk '$Name'"
        $_ = Remove-AzDisk -Name $Name -ResourceGroupName $ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Removed disk '$Name'"
        } else {
            Add-LogMessage -Level Failure "Failed to remove disk '$Name'"
        }
    }
}
Export-ModuleMember -Function Remove-VirtualMachineDisk


# Remove a virtual machine NIC
# ----------------------------
function Remove-VirtualMachineNIC {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of VM NIC to remove")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of resource group to remove from")]
        $ResourceGroupName
    )
    $_ = Get-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level InfoSuccess "VM network card '$Name' does not exist"
    } else {
        Add-LogMessage -Level Info "[ ] Removing VM network card '$Name'"
        $_ = Remove-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Removed VM network card '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to remove VM network card '$Name'"
        }
    }
}
Export-ModuleMember -Function Remove-VirtualMachineNIC


# Set key vault permissions to the group and remove the user who deployed it
# --------------------------------------------------------------------------
function Set-KeyVaultPermissions {
    param(
        [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Name of key vault to set the permissions on")]
        $Name,
        [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Name of group to give permissions to")]
        $GroupName
    )
    Add-LogMessage -Level Info "Setting correct access policies for key vault '$Name'..."
    try {
        $securityGroupId = (Get-AzADGroup -DisplayName $GroupName)[0].Id
    } catch [Microsoft.Azure.Commands.ActiveDirectory.GetAzureADGroupCommand] {
        Add-LogMessage -Level Fatal "Could not identify an Azure security group called $GroupName!"
    }
    Set-AzKeyVaultAccessPolicy -VaultName $Name -ObjectId $securityGroupId `
                               -PermissionsToKeys Get,List,Update,Create,Import,Delete,Backup,Restore,Recover `
                               -PermissionsToSecrets Get,List,Set,Delete,Recover,Backup,Restore `
                               -PermissionsToCertificates Get,List,Delete,Create,Import,Update,Managecontacts,Getissuers,Listissuers,Setissuers,Deleteissuers,Manageissuers,Recover,Backup,Restore
    $success = $?
    foreach ($accessPolicy in (Get-AzKeyVault $Name).AccessPolicies | Where-Object { $_.ObjectId -ne $securityGroupId }) {
        Remove-AzKeyVaultAccessPolicy -VaultName $Name -ObjectId $accessPolicy.ObjectId
        $success = $success -and $?
    }
    if ($success) {
        Add-LogMessage -Level Success "Set correct access policies"
    } else {
        Add-LogMessage -Level Fatal "Failed to set correct access policies!"
    }
}
Export-ModuleMember -Function Set-KeyVaultPermissions


# Attach a network security group to a subnet
# -------------------------------------------
function Set-SubnetNetworkSecurityGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Subnet whose NSG will be set")]
        $Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "Network security group to attach")]
        $NetworkSecurityGroup,
        [Parameter(Mandatory = $true, HelpMessage = "Virtual network that the subnet belongs to")]
        $VirtualNetwork
    )
    Add-LogMessage -Level Info "Ensuring that NSG '$($Nsg.Name)' is attached to subnet '$SubnetName'..."
    $_ = Set-AzVirtualNetworkSubnetConfig -Name $Subnet.Name -VirtualNetwork $VirtualNetwork -AddressPrefix $Subnet.AddressPrefix -NetworkSecurityGroup $NetworkSecurityGroup
    $VirtualNetwork | Set-AzVirtualNetwork
    $success = $?
    $updatedSubnet = Get-AzSubnet -Name $Subnet.Name -VirtualNetwork $VirtualNetwork
    $success = $success -and $?
    if ($success) {
        Add-LogMessage -Level Success "Set correct access policies"
    } else {
        Add-LogMessage -Level Fatal "Failed to set correct access policies!"
    }
    return $updatedSubnet
}
Export-ModuleMember -Function Set-SubnetNetworkSecurityGroup


# Update NSG rule to match a given configuration
# ----------------------------------------------
function Update-NetworkSecurityGroupRule {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of NSG rule to update")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of NSG that this rule belongs to")]
        $NetworkSecurityGroup,
        [Parameter(Mandatory = $false, HelpMessage = "Rule Priority")]
        $Priority = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule direction")]
        [ValidateSet("Inbound", "Outbound")]
        $Direction = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule access type")]
        $Access = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule protocol")]
        $Protocol = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule source address prefix")]
        $SourceAddressPrefix = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule source port range")]
        $SourcePortRange = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule destination address prefix")]
        $DestinationAddressPrefix = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Rule destination port range")]
        $DestinationPortRange = $null
    )
    # Load any unspecified parameters from the existing rule
    try {
        $ruleBefore = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup
        $Description = $ruleBefore.Description
        if ($Priority -eq $null) { $Priority = $ruleBefore.Priority }
        if ($Direction -eq $null) { $Direction = $ruleBefore.Direction }
        if ($Access -eq $null) { $Access = $ruleBefore.Access }
        if ($Protocol -eq $null) { $Protocol = $ruleBefore.Protocol }
        if ($SourceAddressPrefix -eq $null) { $SourceAddressPrefix = $ruleBefore.SourceAddressPrefix }
        if ($SourcePortRange -eq $null) { $SourcePortRange = $ruleBefore.SourcePortRange }
        if ($DestinationAddressPrefix -eq $null) { $DestinationAddressPrefix = $ruleBefore.DestinationAddressPrefix }
        if ($DestinationPortRange -eq $null) { $DestinationPortRange = $ruleBefore.DestinationPortRange }
        # Print the update we're about to make
        if ($Direction -eq "Inbound") {
            Add-LogMessage -Level Info "[ ] Updating '$Name' rule on '$($NetworkSecurityGroup.Name)' to '$Access' access from '$SourceAddressPrefix'"
        } else {
            Add-LogMessage -Level Info "[ ] Updating '$Name' rule on '$($NetworkSecurityGroup.Name)' to '$Access' access to '$DestinationAddressPrefix'"
        }
        # Update rule and NSG (both are required)
        $_ = Set-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup `
                                             -Name "$Name" `
                                             -Description "$Description" `
                                             -Priority "$Priority" `
                                             -Direction "$Direction" `
                                             -Access "$Access" `
                                             -Protocol "$Protocol" `
                                             -SourceAddressPrefix $SourceAddressPrefix `
                                             -SourcePortRange $SourcePortRange `
                                             -DestinationAddressPrefix $DestinationAddressPrefix `
                                             -DestinationPortRange $DestinationPortRange | Set-AzNetworkSecurityGroup
        # Apply the rule and validate whether it succeeded
        $ruleAfter = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup
        if (($ruleAfter.Name -eq $Name) -and
            ($ruleAfter.Description -eq $Description) -and
            ($ruleAfter.Priority -eq $Priority) -and
            ($ruleAfter.Direction -eq $Direction) -and
            ($ruleAfter.Access -eq $Access) -and
            ($ruleAfter.Protocol -eq $Protocol) -and
            ("$($ruleAfter.SourceAddressPrefix)" -eq "$SourceAddressPrefix") -and
            ("$($ruleAfter.SourcePortRange)" -eq "$SourcePortRange") -and
            ("$($ruleAfter.DestinationAddressPrefix)" -eq "$DestinationAddressPrefix") -and
            ("$($ruleAfter.DestinationPortRange)" -eq "$DestinationPortRange")) {
            if ($Direction -eq "Inbound") {
                Add-LogMessage -Level Success "'$Name' on '$($NetworkSecurityGroup.Name)' will now '$($ruleAfter.Access)' access from '$($ruleAfter.SourceAddressPrefix)'"
            } else {
                Add-LogMessage -Level Success "'$Name' on '$($NetworkSecurityGroup.Name)' will now '$($ruleAfter.Access)' access to '$($ruleAfter.DestinationAddressPrefix)'"
            }
        } else {
            if ($Direction -eq "Inbound") {
                Add-LogMessage -Level Failure "'$Name' on '$($NetworkSecurityGroup.Name)' will now '$($ruleAfter.Access)' access from '$($ruleAfter.SourceAddressPrefix)'"
            } else {
                Add-LogMessage -Level Failure "'$Name' on '$($NetworkSecurityGroup.Name)' will now '$($ruleAfter.Access)' access to '$($ruleAfter.DestinationAddressPrefix)'"
            }
        }
        # Return the rule
        return $ruleAfter
    } catch [System.Management.Automation.ValidationMetadataException] {
        Add-LogMessage -Level Fatal "Could not find rule '$Name' on NSG '$($NetworkSecurityGroup.Name)'"
    }
}
Export-ModuleMember -Function Update-NetworkSecurityGroupRule
