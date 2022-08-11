Import-Module Az.Compute -ErrorAction Stop
Import-Module $PSScriptRoot/AzureNetwork -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Confirm VM is deallocated
# -------------------------
function Confirm-VmDeallocated {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        [string]$ResourceGroupName
    )
    $vmStatuses = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status).Statuses.Code
    return (($vmStatuses -contains "PowerState/deallocated") -and ($vmStatuses -contains "ProvisioningState/succeeded"))
}
Export-ModuleMember -Function Confirm-VmDeallocated


# Confirm VM is running
# ---------------------
function Confirm-VmRunning {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        [string]$ResourceGroupName
    )
    $vmStatuses = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status).Statuses.Code
    return (($vmStatuses -contains "PowerState/running") -and ($vmStatuses -contains "ProvisioningState/succeeded"))
}
Export-ModuleMember -Function Confirm-VmRunning


# Confirm VM is stopped
# ---------------------
function Confirm-VmStopped {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        [string]$ResourceGroupName
    )
    if ($vmStatuses -contains "ProvisioningState/failed/VMStoppedToWarnSubscription") {
        Add-LogMessage -Level Warning "VM '$Name' has status: VMStoppedToWarnSubscription meaning that it was automatically stopped when the subscription ran out of credit."
    }
    $vmStatuses = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status).Statuses.Code
    return (($vmStatuses -contains "PowerState/stopped") -and (($vmStatuses -contains "ProvisioningState/succeeded") -or ($vmStatuses -contains "ProvisioningState/failed/VMStoppedToWarnSubscription")))
}
Export-ModuleMember -Function Confirm-VmStopped


# Create Linux virtual machine if it does not exist
# -------------------------------------------------
function Deploy-LinuxVirtualMachine {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Administrator password")]
        [System.Security.SecureString]$AdminPassword,
        [Parameter(Mandatory = $true, HelpMessage = "Administrator username")]
        [string]$AdminUsername,
        [Parameter(Mandatory = $true, HelpMessage = "Name of storage account for boot diagnostics")]
        [Microsoft.Azure.Commands.Management.Storage.Models.PSStorageAccount]$BootDiagnosticsAccount,
        [Parameter(Mandatory = $true, HelpMessage = "Cloud-init YAML file")]
        [string]$CloudInitYaml,
        [Parameter(Mandatory = $true, ParameterSetName = "ByNicId_ByImageId", HelpMessage = "ID of VM image to deploy")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageId", HelpMessage = "ID of VM image to deploy")]
        [string]$ImageId,
        [Parameter(Mandatory = $true, ParameterSetName = "ByNicId_ByImageSku", HelpMessage = "SKU of VM image to deploy")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageSku", HelpMessage = "SKU of VM image to deploy")]
        [string]$ImageSku,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        [string]$Location,
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual machine to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, ParameterSetName = "ByNicId_ByImageId", HelpMessage = "ID of network card to attach to this VM")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByNicId_ByImageSku", HelpMessage = "ID of network card to attach to this VM")]
        [string]$NicId,
        [Parameter(Mandatory = $true, HelpMessage = "OS disk type (eg. Standard_LRS)")]
        [string]$OsDiskType,
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageId", HelpMessage = "Private IP address to assign to this VM")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageSku", HelpMessage = "Private IP address to assign to this VM")]
        [string]$PrivateIpAddress,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Size of virtual machine to deploy")]
        [string]$Size,
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageId", HelpMessage = "Subnet to deploy this VM into")]
        [Parameter(Mandatory = $true, ParameterSetName = "ByIpAddress_ByImageSku", HelpMessage = "Subnet to deploy this VM into")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet,
        [Parameter(Mandatory = $false, HelpMessage = "Administrator public SSH key")]
        [string]$AdminPublicSshKey = $null,
        [Parameter(Mandatory = $false, HelpMessage = "IDs of data disks")]
        [string[]]$DataDiskIds = $null,
        [Parameter(Mandatory = $false, HelpMessage = "Do not wait for deployment to finish")]
        [switch]$NoWait = $false,
        [Parameter(Mandatory = $false, HelpMessage = "Size of OS disk (GB)")]
        [int]$OsDiskSizeGb = $null
    )
    Add-LogMessage -Level Info "Ensuring that virtual machine '$Name' exists..."
    $null = Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        $adminCredentials = New-Object System.Management.Automation.PSCredential("$AdminUsername", $AdminPassword)
        # Build VM configuration
        $vmConfig = New-AzVMConfig -VMName $Name -VMSize $Size
        # Set source image to a custom image or to latest Ubuntu (default)
        if ($ImageId) {
            $vmConfig = Set-AzVMSourceImage -VM $vmConfig -Id $ImageId
        } elseif ($ImageSku) {
            if (($ImageSku -eq "Ubuntu-20.04") -or ($ImageSku -eq "Ubuntu-latest")) {
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName Canonical -Offer 0001-com-ubuntu-server-focal -Skus "20_04-LTS" -Version "latest"
            } elseif ($ImageSku -eq "Ubuntu-18.04") {
                $vmConfig = Set-AzVMSourceImage -VM $vmConfig -PublisherName Canonical -Offer UbuntuServer -Skus "18.04-LTS" -Version "latest"
            }
        }
        if (-not $vmConfig) {
            Add-LogMessage -Level Fatal "Could not determine which source image to use!"
        }
        $vmConfig = Set-AzVMOperatingSystem -VM $vmConfig -Linux -ComputerName $Name -Credential $adminCredentials -CustomData $CloudInitYaml
        if (-not $NicId) {
            $NicId = (Deploy-NetworkInterface -Name "${Name}-NIC" -ResourceGroupName $ResourceGroupName -Subnet $Subnet -PrivateIpAddress $PrivateIpAddress -Location $Location).Id
        }
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
            $lun += 1 # NB. this line means that our first disk gets deployed at lun1 and we do not use lun0. Consider changing this.
            $vmConfig = Add-AzVMDataDisk -VM $vmConfig -ManagedDiskId $diskId -CreateOption Attach -Lun $lun
        }
        # Copy public key to VM
        if ($AdminPublicSshKey) {
            $vmConfig = Add-AzVMSshPublicKey -VM $vmConfig -KeyData $AdminPublicSshKey -Path "/home/$($AdminUsername)/.ssh/authorized_keys"
        }
        # Create VM
        Add-LogMessage -Level Info "[ ] Creating virtual machine '$Name'"
        try {
            $null = New-AzVM -ResourceGroupName $ResourceGroupName -Location $Location -VM $vmConfig -ErrorAction Stop
            Add-LogMessage -Level Success "Created virtual machine '$Name'"
        } catch {
            Add-LogMessage -Level Fatal "Failed to create virtual machine '$Name'! Check that your desired image is available in this region." -Exception $_.Exception
        }
        if (-not $NoWait) {
            Start-Sleep 30  # wait for VM deployment to register
            Wait-ForCloudInit -Name $Name -ResourceGroupName $ResourceGroupName
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Virtual machine '$Name' already exists"
    }
    return (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName)
}
Export-ModuleMember -Function Deploy-LinuxVirtualMachine


# Create a managed disk if it does not exist
# ------------------------------------------
function Deploy-ManagedDisk {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of disk to deploy")]
        $Name,
        [Parameter(Mandatory = $true, HelpMessage = "Disk size in GB")]
        $SizeGB,
        [Parameter(Mandatory = $true, HelpMessage = "Disk type (eg. Standard_LRS)")]
        $Type,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        $ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
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


# Deploy Azure Monitoring Extension on a VM
# -----------------------------------------
function Deploy-VirtualMachineMonitoringExtension {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "VM object")]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM,
        [Parameter(Mandatory = $true, HelpMessage = "Log Analytics Workspace ID")]
        [string]$WorkspaceId,
        [Parameter(Mandatory = $true, HelpMessage = "Log Analytics Workspace key")]
        [string]$WorkspaceKey
    )
    if ($VM.OSProfile.WindowsConfiguration) {
        # Install Monitoring Agent
        Set-VirtualMachineExtensionIfNotInstalled -VM $VM -Publisher "Microsoft.EnterpriseCloud.Monitoring" -Type "MicrosoftMonitoringAgent" -Version 1.0 -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey
        # # Install Dependency Agent
        # Set-VirtualMachineExtensionIfNotInstalled -VM $VM -Publisher "Microsoft.Azure.Monitoring.DependencyAgent" -Type "DependencyAgentWindows" -Version 9.10 -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey
    } elseif ($VM.OSProfile.LinuxConfiguration) {
        # Install Monitoring Agent
        Set-VirtualMachineExtensionIfNotInstalled -VM $VM -Publisher "Microsoft.EnterpriseCloud.Monitoring" -Type "OmsAgentForLinux" -EnableAutomaticUpgrade $true -Version 1.14 -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey
        # # Install Dependency Agent - not working with current Ubuntu 20.04 (https://docs.microsoft.com/en-us/answers/questions/938560/unable-to-enable-insights-on-ubuntu-2004-server.html)
        # Set-VirtualMachineExtensionIfNotInstalled -VM $VM -Publisher "Microsoft.Azure.Monitoring.DependencyAgent" -Type "DependencyAgentLinux" -Version 9.10 -WorkspaceId $WorkspaceId -WorkspaceKey $WorkspaceKey
    } else {
        Add-LogMessage -Level Fatal "VM OSProfile not recognised. Cannot activate logging for VM '$($vm.Name)'!"
    }
}
Export-ModuleMember -Function Deploy-VirtualMachineMonitoringExtension


# Get image ID
# ------------
function Get-ImageFromGallery {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Image version to retrieve")]
        [string]$ImageVersion,
        [Parameter(Mandatory = $true, HelpMessage = "Image definition that image belongs to")]
        [string]$ImageDefinition,
        [Parameter(Mandatory = $true, HelpMessage = "Image gallery name")]
        [string]$GalleryName,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group containing image gallery")]
        [string]$ResourceGroup,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription containing image gallery")]
        [string]$Subscription
    )
    $originalContext = Get-AzContext
    try {
        $null = Set-AzContext -Subscription $Subscription -ErrorAction Stop
        Add-LogMessage -Level Info "Looking for image $imageDefinition version $imageVersion..."
        try {
            $image = Get-AzGalleryImageVersion -ResourceGroup $ResourceGroup -GalleryName $GalleryName -GalleryImageDefinitionName $ImageDefinition -GalleryImageVersionName $ImageVersion -ErrorAction Stop
        } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
            $versions = Get-AzGalleryImageVersion -ResourceGroup $ResourceGroup -GalleryName $GalleryName -GalleryImageDefinitionName $ImageDefinition | Sort-Object Name | ForEach-Object { $_.Name }
            Add-LogMessage -Level Error "Image version '$ImageVersion' is invalid. Available versions are: $versions"
            $ImageVersion = $versions | Select-Object -Last 1
            $userVersion = Read-Host -Prompt "Enter the version you would like to use (or leave empty to accept the default: '$ImageVersion')"
            if ($versions.Contains($userVersion)) {
                $ImageVersion = $userVersion
            }
            $image = Get-AzGalleryImageVersion -ResourceGroup $ResourceGroup -GalleryName $GalleryName -GalleryImageDefinitionName $ImageDefinition -GalleryImageVersionName $ImageVersion -ErrorAction Stop
        }
        if ($image) {
            $commitHash = $image.Tags["Build commit hash"]
            if ($commitHash) {
                Add-LogMessage -Level Success "Found image $imageDefinition version $($image.Name) in gallery created from commit $commitHash"
            } else {
                Add-LogMessage -Level Success "Found image $imageDefinition version $($image.Name) in gallery"
            }
        } else {
            Add-LogMessage -Level Fatal "Could not find image $imageDefinition version $ImageVersion in gallery!"
        }
    } catch {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
        throw
    } finally {
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
    return $image
}
Export-ModuleMember -Function Get-ImageFromGallery


# Set Azure Monitoring Extension on a VM
# --------------------------------------
function Set-VirtualMachineExtensionIfNotInstalled {
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Extension publisher")]
        [boolean]$EnableAutomaticUpgrade = $false,
        [Parameter(Mandatory = $true, HelpMessage = "Extension publisher")]
        [string]$Publisher,
        [Parameter(Mandatory = $true, HelpMessage = "Extension type")]
        [string]$Type,
        [Parameter(Mandatory = $true, HelpMessage = "Extension version")]
        [string]$Version,
        [Parameter(Mandatory = $true, HelpMessage = "VM object")]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM,
        [Parameter(Mandatory = $true, HelpMessage = "Log Analytics Workspace ID")]
        [string]$WorkspaceId,
        [Parameter(Mandatory = $true, HelpMessage = "Log Analytics Workspace key")]
        [string]$WorkspaceKey
    )
    Add-LogMessage -Level Info "[ ] Ensuring extension '$type' is installed on VM '$($VM.Name)'."
    $extension = Get-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -ErrorAction SilentlyContinue | Where-Object { $_.Publisher -eq $Publisher -and $_.ExtensionType -eq $Type }
    if ($extension -and $extension.ProvisioningState -ne "Succeeded") {
        Add-LogMessage -Level Warning "Removing misconfigured extension '$type' installation on VM '$($VM.Name)'."
        $null = Remove-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Name $Type -Force
        $extension = Get-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Name $Type -ErrorAction SilentlyContinue
    }
    if ($extension) {
        Add-LogMessage -Level InfoSuccess "Extension '$type' is already installed on VM '$($VM.Name)'."
    } else {
        foreach ($i in 1..5) {
            try {
                $null = Set-AzVMExtension -EnableAutomaticUpgrade $EnableAutomaticUpgrade `
                                          -ExtensionName $type `
                                          -ExtensionType $type `
                                          -Location $VM.location `
                                          -ProtectedSettings @{ "workspaceKey" = $WorkspaceKey } `
                                          -Publisher $publisher `
                                          -ResourceGroupName $VM.ResourceGroupName `
                                          -Settings @{ "workspaceId" = $WorkspaceId } `
                                          -TypeHandlerVersion $version `
                                          -VMName $VM.Name `
                                          -ErrorAction Stop
                Start-Sleep 10
                $extension = Get-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Name $Type -ErrorAction Stop
                if ($extension -and $extension.ProvisioningState -eq "Succeeded") {
                    break
                }
            } catch {
                $exception = $_.Exception
                Start-Sleep 30
            }
        }
        $extension = Get-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Name $Type -ErrorAction Stop
        if ($extension -and $extension.ProvisioningState -eq "Succeeded") {
            Add-LogMessage -Level Success "Installed extension '$type' on VM '$($VM.Name)'."
        } else {
            if ($exception) {
                Add-LogMessage -Level Fatal "Failed to install extension '$type' on VM '$($VM.Name)'!" -Exception $exception
            } else {
                Add-LogMessage -Level Fatal "Failed to install extension '$type' on VM '$($VM.Name)'!"
            }
        }
    }
}
Export-ModuleMember -Function Set-VirtualMachineExtensionIfNotInstalled


# Ensure VM is started, with option to force a restart
# ----------------------------------------------------
function Start-VM {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM object", ParameterSetName = "ByObject")]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM,
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM name", ParameterSetName = "ByName")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM resource group", ParameterSetName = "ByName")]
        [string]$ResourceGroupName,
        [Parameter(HelpMessage = "Skip this VM if it does not exist")]
        [switch]$SkipIfNotExist,
        [Parameter(HelpMessage = "Force restart of VM if already running")]
        [switch]$ForceRestart,
        [Parameter(HelpMessage = "Don't wait for VM (re)start operation to complete before returning")]
        [switch]$NoWait
    )
    # Get VM if not provided
    if (-not $VM) {
        try {
            $VM = Get-AzVM -Name $Name -ResourceGroup $ResourceGroupName -ErrorAction Stop
        } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
            if ($SkipIfNotExist) { return }
            Add-LogMessage -Level Fatal "VM '$Name' could not be found in resource group '$ResourceGroupName'" -Exception $_.Exception
        }
    }
    # Ensure VM is started but don't restart if already running
    $operation = "start"
    if (Confirm-VmRunning -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName) {
        if ($ForceRestart) {
            $operation = "restart"
            Add-LogMessage -Level Info "[ ] Restarting VM '$($VM.Name)'"
            $result = Restart-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -NoWait:$NoWait
        } else {
            Add-LogMessage -Level InfoSuccess "VM '$($VM.Name)' already running."
            return
        }
    } elseif ((Confirm-VmDeallocated -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName) -or (Confirm-VmStopped -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName)) {
        Add-LogMessage -Level Info "[ ] Starting VM '$($VM.Name)'"
        $result = Start-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -NoWait:$NoWait
    } else {
        $vmStatus = (Get-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Status).Statuses.Code
        Add-LogMessage -Level Warning "VM '$($VM.Name)' not in supported status: $vmStatus. No action taken."
        return
    }
    if ($result -is [Microsoft.Azure.Commands.Compute.Models.PSComputeLongRunningOperation]) {
        # Synchronous operation requested
        if ($result.Status -eq "Succeeded") {
            Add-LogMessage -Level Success "VM '$($VM.Name)' successfully ${operation}ed."
        } else {
            # If (re)start failed, log error with failure reason
            Add-LogMessage -Level Fatal "Failed to ${operation} VM '$($VM.Name)' [$($result.StatusCode): $($result.ReasonPhrase)]"
        }
    } elseif ($result -is [Microsoft.Azure.Commands.Compute.Models.PSAzureOperationResponse]) {
        # Asynchronous operation requested
        if (-not $result.IsSuccessStatusCode) {
            Add-LogMessage -Level Fatal "Request to ${operation} VM '$($VM.Name)' failed [$($result.StatusCode): $($result.ReasonPhrase)]"
        } else {
            Add-LogMessage -Level Success "Request to ${operation} VM '$($VM.Name)' accepted."
        }
    } else {
        Add-LogMessage -Level Fatal "Unrecognised return type from operation: '$($result.GetType().Name)'."
    }
}
Export-ModuleMember -Function Start-VM


# Ensure VM is stopped (de-allocated)
# -----------------------------------
function Stop-VM {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM object", ParameterSetName = "ByObject")]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM,
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM name", ParameterSetName = "ByName")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM resource group", ParameterSetName = "ByName")]
        [string]$ResourceGroupName,
        [Parameter(HelpMessage = "Skip this VM if it does not exist")]
        [switch]$SkipIfNotExist,
        [Parameter(HelpMessage = "Don't wait for VM deallocation operation to complete before returning")]
        [switch]$NoWait
    )
    # Get VM if not provided
    if (-not $VM) {
        try {
            $VM = Get-AzVM -Name $Name -ResourceGroup $ResourceGroupName -ErrorAction Stop
        } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
            if ($SkipIfNotExist) { return }
            Add-LogMessage -Level Fatal "VM '$Name' could not be found in resource group '$ResourceGroupName'" -Exception $_.Exception
        }
    }
    # Ensure VM is deallocated
    if (Confirm-VmDeallocated -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName) {
        Add-LogMessage -Level InfoSuccess "VM '$($VM.Name)' already stopped."
        return
    } else {
        Add-LogMessage -Level Info "[ ] Stopping VM '$($VM.Name)'"
        $result = Stop-AzVM -Name $VM.Name -ResourceGroupName $VM.ResourceGroupName -Force -NoWait:$NoWait
    }
    if ($result -is [Microsoft.Azure.Commands.Compute.Models.PSComputeLongRunningOperation]) {
        # Synchronous operation requested
        if ($result.Status -eq "Succeeded") {
            Add-LogMessage -Level Success "VM '$($VM.Name)' stopped."
        } else {
            Add-LogMessage -Level Fatal "Failed to stop VM '$($VM.Name)' [$($result.Status): $($result.Error)]"
        }
    } elseif ($result -is [Microsoft.Azure.Commands.Compute.Models.PSAzureOperationResponse]) {
        # Asynchronous operation requested
        if (-not $result.IsSuccessStatusCode) {
            Add-LogMessage -Level Fatal "Request to stop VM '$($VM.Name)' failed [$($result.StatusCode): $($result.ReasonPhrase)]"
        } else {
            Add-LogMessage -Level Success "Request to stop VM '$($VM.Name)' accepted."
        }
    } else {
        Add-LogMessage -Level Fatal "Unrecognised return type from operation: '$($result.GetType().Name)'."
    }
}
Export-ModuleMember -Function Stop-VM


# Wait for cloud-init provisioning to finish
# ------------------------------------------
function Wait-ForCloudInit {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual machine to wait for")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group VM belongs to")]
        [string]$ResourceGroupName
    )
    # Poll VM to see whether it has finished running
    Add-LogMessage -Level Info "Waiting for cloud-init provisioning to finish for $Name..."
    $progress = 0
    $statuses = @()
    while (-not ($statuses.Contains("ProvisioningState/succeeded") -and ($statuses.Contains("PowerState/stopped") -or $statuses.Contains("PowerState/deallocated")))) {
        try {
            $statuses = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status -ErrorAction Stop).Statuses.Code
        } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
            Add-LogMessage -Level Fatal "Could not retrieve VM status while waiting for cloud-init to finish!" -Exception $_.Exception
        } catch {
            Add-LogMessage -Level Fatal "Unknown error of type $($_.Exception.GetType()) occurred!" -Exception $_.Exception
        }
        $progress = [math]::min(100, $progress + 1)
        Write-Progress -Activity "Deployment status" -Status "$($statuses[0]) $($statuses[1])" -PercentComplete $progress
        Start-Sleep 10
    }
    Add-LogMessage -Level Success "Cloud-init provisioning is finished for $Name"
}
Export-ModuleMember -Function Wait-ForCloudInit
