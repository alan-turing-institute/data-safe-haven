Import-Module Az.Compute -ErrorAction Stop
Import-Module $PSScriptRoot/AzureNetwork -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


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
