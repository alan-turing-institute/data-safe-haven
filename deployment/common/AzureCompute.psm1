Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop
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


# Get all VMs for an SHM or SRE
# -----------------------------
function Get-VMsByResourceGroupPrefix {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Prefix to match resource groups on")]
        [string]$ResourceGroupPrefix
    )
    $matchingResourceGroups = Get-AzResourceGroup | Where-Object { $_.ResourceGroupName -like "${ResourceGroupPrefix}_*" }
    $matchingVMs = [ordered]@{}
    foreach ($rg in $matchingResourceGroups) {
        $rgVms = Get-AzVM -ResourceGroup $rg.ResourceGroupName
        if ($rgVms) {
            $matchingVMs[$rg.ResourceGroupName] = $rgVms
        }
    }
    return $matchingVMs
}
Export-ModuleMember -Function Get-VMsByResourceGroupPrefix


# Run remote shell script
# -----------------------
function Invoke-RemoteScript {
    param(
        [Parameter(Mandatory = $true, ParameterSetName = "ByPath", HelpMessage = "Path to local script that will be run remotely")]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true, ParameterSetName = "ByString", HelpMessage = "Contents of script that will be run remotely")]
        [string]$Script,
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to run on")]
        [string]$VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group VM belongs to")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $false, HelpMessage = "Type of script to run")]
        [ValidateSet("PowerShell", "UnixShell")]
        [string]$Shell = "PowerShell",
        [Parameter(Mandatory = $false, HelpMessage = "Suppress script output on success")]
        [switch]$SuppressOutput,
        [Parameter(Mandatory = $false, HelpMessage = "(Optional) hashtable of script parameters")]
        [System.Collections.IDictionary]$Parameter = $null
    )
    # If we're given a script then create a file from it
    $tmpScriptFile = $null
    if ($Script) {
        $tmpScriptFile = New-TemporaryFile
        $Script | Out-File -FilePath $tmpScriptFile.FullName
        $ScriptPath = $tmpScriptFile.FullName
    }
    # Validate any external parameters as non-string arguments or arguments containing special characters will cause Invoke-AzVMRunCommand to fail
    $params = @{}
    if ($Parameter) { $params["Parameter"] = $Parameter }
    $params["CommandId"] = ($Shell -eq "PowerShell") ? "RunPowerShellScript" : "RunShellScript"
    if ($params.Contains("Parameter")) {
        foreach ($kv in $params["Parameter"].GetEnumerator()) {
            if ($kv.Value -isnot [string]) {
                Add-LogMessage -Level Fatal "$($kv.Key) argument ($($kv.Value)) must be a string!"
            }
            foreach ($unsafeCharacter in @("|", "&")) {
                if ($kv.Value.Contains($unsafeCharacter)) {
                    Add-LogMessage -Level Fatal "$($kv.Key) argument ($($kv.Value)) contains '$unsafeCharacter' which will cause Invoke-AzVMRunCommand to fail. Consider encoding this variable in Base-64."
                }
            }
            foreach ($whitespaceCharacter in @(" ", "`t")) {
                if (($Shell -eq "UnixShell") -and ($kv.Value.Contains($whitespaceCharacter))) {
                    if (-not (($kv.Value[0] -eq "'") -or ($kv.Value[0] -eq '"'))) {
                        Write-Information -InformationAction "Continue" $kv.Value[0]
                        Add-LogMessage -Level Fatal "$($kv.Key) argument ($($kv.Value)) contains '$whitespaceCharacter' which will cause the shell script to fail. Consider wrapping this variable in single quotes."
                    }
                }
            }
        }
    }
    try {
        # Catch failures from running two commands in close proximity and rerun
        while ($true) {
            try {
                $result = Invoke-AzVMRunCommand -Name $VMName -ResourceGroupName $ResourceGroupName -ScriptPath $ScriptPath @params -ErrorAction Stop
                $success = $?
                break
            } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
               if (-not ($_.Exception.Message -match "Run command extension execution is in progress")) { throw }
            }
        }
    } catch {
        Add-LogMessage -Level Fatal "Running '$ScriptPath' on remote VM '$VMName' failed." -Exception $_.Exception
    }
    $success = $success -and ($result.Status -eq "Succeeded")
    foreach ($outputStream in $result.Value) {
        # Check for 'ComponentStatus/<stream name>/succeeded' as a signal of success
        $success = $success -and (($outputStream.Code -split "/")[-1] -eq "succeeded")
        # Check for ' [x] ' in the output stream as a signal of failure
        if ($outputStream.Message -ne "") {
            $success = $success -and ([string]($outputStream.Message) -NotLike '* `[x`] *')
        }
    }
    # Clean up any temporary scripts
    if ($tmpScriptFile) { Remove-Item $tmpScriptFile.FullName }
    # Check for success or failure
    if ($success) {
        Add-LogMessage -Level Success "Remote script execution succeeded"
        if (-not $SuppressOutput) { Write-Information -InformationAction "Continue" ($result.Value | Out-String) }
    } else {
        Add-LogMessage -Level Info "Script output:"
        Write-Information -InformationAction "Continue" ($result | Out-String)
        Add-LogMessage -Level Fatal "Remote script execution has failed. Please check the output above before re-running this script."
    }
    return $result
}
Export-ModuleMember -Function Invoke-RemoteScript


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


# Run Azure desired state configuration
# -------------------------------------
function Invoke-AzureVmDesiredState {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of configuration file previously uploaded with Publish-AzVMDscConfiguration.")]
        [string]$ArchiveBlobName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Azure storage container where the configuration archive is located.")]
        [string]$ArchiveContainerName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that contains the storage account containing the configuration archive.")]
        [string]$ArchiveResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Azure storage account containing the configuration archive.")]
        [string]$ArchiveStorageAccountName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the configuration function being invoked")]
        [string]$ConfigurationName,
        [Parameter(Mandatory = $false, HelpMessage = "Hash table that contains the arguments to the configuration function")]
        [System.Collections.Hashtable]$ConfigurationParameters,
        [Parameter(Mandatory = $true, HelpMessage = "Location of the VM being configured")]
        [string]$VmLocation,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the VM being configured")]
        [string]$VmName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that contains the VM being configured")]
        [string]$VmResourceGroupName
    )
    # Run remote configuration
    Add-LogMessage -Level Info "Running desired state configuration '$ConfigurationName' on VM '$VmName'."
    $params = @{}
    if ($ConfigurationParameters) { $params["ConfigurationArgument"] = $ConfigurationParameters }
    $maxTries = 3
    for ($attempt = 1; $attempt -le $maxTries; $attempt++) {
        try {
            $result = Set-AzVMDscExtension -ArchiveBlobName $ArchiveBlobName `
                                           -ArchiveContainerName $ArchiveContainerName `
                                           -ArchiveResourceGroupName $ArchiveResourceGroupName `
                                           -ArchiveStorageAccountName $ArchiveStorageAccountName `
                                           -ConfigurationName $ConfigurationName `
                                           -Location $VmLocation `
                                           -Name "DataSafeHavenDesiredState" `
                                           -ResourceGroupName $VmResourceGroupName `
                                           -Version "2.77" `
                                           -VMName $VmName `
                                           @params
            break
        } catch {
            Add-LogMessage -Level Info "Applying desired state configuration failed. Attempt [$attempt/$maxTries]."
            $ErrorMessage = $_.Exception
        }
    }
    # Check for success or failure
    if ($result.IsSuccessStatusCode) {
        Add-LogMessage -Level Success "Ran desired state configuration '$ConfigurationName' on VM '$VmName'."
    } else {
        Add-LogMessage -Level Fatal "Failed to run desired state configuration '$ConfigurationName' on VM '$VmName'!`n${ErrorMessage}"
    }
    return $result
}
Export-ModuleMember -Function Invoke-AzureVmDesiredState


# Remove Virtual Machine disk
# ---------------------------
function Remove-ManagedDisk {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the disk to remove")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group containing the disk")]
        [string]$ResourceGroupName
    )

    $null = Get-AzDisk -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level InfoSuccess "Disk '$Name' does not exist"
    } else {
        Add-LogMessage -Level Info "[ ] Removing disk '$Name'"
        $null = Remove-AzDisk -Name $Name -ResourceGroupName $ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Removed disk '$Name'"
        } else {
            Add-LogMessage -Level Failure "Failed to remove disk '$Name'"
        }
    }
}
Export-ModuleMember -Function Remove-ManagedDisk


# Remove Virtual Machine
# ----------------------
function Remove-VirtualMachine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of the VM to remove")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group containing the VM")]
        [string]$ResourceGroupName,
        [Parameter(HelpMessage = "Forces the command to run without asking for user confirmation.")]
        [switch]$Force
    )
    $vm = Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
    if ($vm) {
        # Get boot diagnostics details
        $storageAccountName = [regex]::match($vm.DiagnosticsProfile.bootDiagnostics.storageUri, '^http[s]?://(.+?)\.').Groups[1].Value
        $bootDiagnosticsContainerName = "bootdiagnostics-*-$($vm.VmId)"
        # Remove VM
        Add-LogMessage -Level Info "[ ] Removing VM '$($vm.Name)'"
        $params = @{}
        if ($Force) { $params["Force"] = $Force }
        if ($ErrorAction) { $params["ErrorAction"] = $ErrorAction }
        $null = $vm | Remove-AzVM @params
        $success = $?
        # Remove boot diagnostics container
        Add-LogMessage -Level Info "[ ] Removing boot diagnostics account for '$($vm.Name)'"
        $storageAccount = Get-AzStorageAccount | Where-Object { $_.StorageAccountName -eq $storageAccountName }
        $null = $storageAccount | Get-AzStorageContainer | Where-Object { $_.Name -like $bootDiagnosticsContainerName } | Remove-AzStorageContainer -Force
        $success = $success -and $?
        if ($success) {
            Add-LogMessage -Level Success "Removed VM '$Name'"
        } else {
            Add-LogMessage -Level Failure "Failed to remove VM '$Name'"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "VM '$Name' does not exist"
    }
}
Export-ModuleMember -Function Remove-VirtualMachine


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
