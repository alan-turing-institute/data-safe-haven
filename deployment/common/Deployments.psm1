Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Dns -ErrorAction Stop
Import-Module Az.KeyVault -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module Az.OperationalInsights -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module Az.Storage -ErrorAction Stop
Import-Module $PSScriptRoot/AzureCompute -ErrorAction Stop
Import-Module $PSScriptRoot/AzureNetwork -ErrorAction Stop
Import-Module $PSScriptRoot/DataStructures -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Associate a VM to an NSG
# ------------------------
function Add-VmToNSG {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual machine")]
        [string]$VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of network security group")]
        [string]$NSGName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        [string]$VmResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the NSG belongs to")]
        [string]$NsgResourceGroupName,
        [Parameter(Mandatory = $false, HelpMessage = "Allow failures, printing a warning message instead of throwing an exception")]
        [switch]$WarnOnFailure
    )
    $LogLevel = $WarnOnFailure ? "Warning" : "Fatal"
    Add-LogMessage -Level Info "[ ] Associating $VMName with $NSGName..."
    $matchingVMs = Get-AzVM -Name $VMName -ResourceGroupName $VmResourceGroupName -ErrorAction SilentlyContinue
    if ($matchingVMs.Count -ne 1) { Add-LogMessage -Level $LogLevel "Found $($matchingVMs.Count) VM(s) called $VMName!"; return }
    $networkCard = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $matchingVMs[0].Id }
    $nsg = Get-AzNetworkSecurityGroup -Name $NSGName -ResourceGroupName $NsgResourceGroupName -ErrorAction SilentlyContinue
    if ($nsg.Count -ne 1) { Add-LogMessage -Level $LogLevel "Found $($nsg.Count) NSG(s) called $NSGName!"; return }
    $networkCard.NetworkSecurityGroup = $nsg
    $null = ($networkCard | Set-AzNetworkInterface)
    if ($?) {
        Start-Sleep -Seconds 10  # Allow NSG association to propagate
        Add-LogMessage -Level Success "NSG association succeeded"
    } else {
        Add-LogMessage -Level Fatal "NSG association failed!"
    }
}
Export-ModuleMember -Function Add-VmToNSG


# Create virtual network if it does not exist
# ------------------------------------------
function Deploy-VirtualNetwork {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual network to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies a range of IP addresses for a virtual network")]
        [string]$AddressPrefix,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        [string]$Location,
        [Parameter(Mandatory = $false, HelpMessage = "DNS servers to attach to this virtual network")]
        [string[]]$DnsServer
    )
    Add-LogMessage -Level Info "Ensuring that virtual network '$Name' exists..."
    $vnet = Get-AzVirtualNetwork -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating virtual network '$Name'"
        $params = @{}
        if ($DnsServer) { $params["DnsServer"] = $DnsServer }
        $vnet = New-AzVirtualNetwork -Name $Name -Location $Location -ResourceGroupName $ResourceGroupName -AddressPrefix "$AddressPrefix" @params -Force
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


# Create virtual network gateway if it does not exist
# ---------------------------------------------------
function Deploy-VirtualNetworkGateway {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual network gateway to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Location of resource group to deploy")]
        [string]$Location,
        [Parameter(Mandatory = $true, HelpMessage = "ID of the public IP address to use")]
        [string]$PublicIpAddressId,
        [Parameter(Mandatory = $true, HelpMessage = "ID of the subnet to deploy into")]
        [string]$SubnetId,
        [Parameter(Mandatory = $true, HelpMessage = "Point-to-site certificate used by the gateway")]
        [string]$P2SCertificate,
        [Parameter(Mandatory = $true, HelpMessage = "Range of IP addresses used by the point-to-site VpnClient")]
        [string]$VpnClientAddressPool
    )
    Add-LogMessage -Level Info "Ensuring that virtual network gateway '$Name' exists..."
    $gateway = Get-AzVirtualNetworkGateway -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating virtual network gateway '$Name'..."
        $ipconfig = New-AzVirtualNetworkGatewayIpConfig -Name "shmgwipconf" -SubnetId $SubnetId -PublicIpAddressId $PublicIpAddressId
        $rootCertificate = New-AzVpnClientRootCertificate -Name "SafeHavenManagementP2SRootCert" -PublicCertData $P2SCertificate
        $gateway = New-AzVirtualNetworkGateway -Name $Name `
                                               -GatewaySku VpnGw1 `
                                               -GatewayType Vpn `
                                               -IpConfigurations $ipconfig `
                                               -Location $Location `
                                               -ResourceGroupName $ResourceGroupName `
                                               -VpnClientAddressPool $VpnClientAddressPool `
                                               -VpnClientProtocol IkeV2, SSTP `
                                               -VpnClientRootCertificates $rootCertificate `
                                               -VpnType RouteBased
        if ($?) {
            Add-LogMessage -Level Success "Created virtual network gateway '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create virtual network gateway '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Virtual network gateway '$Name' already exists"
    }
    return $gateway
}
Export-ModuleMember -Function Deploy-VirtualNetworkGateway


# Ensure that an Azure VM is turned on
# ------------------------------------
function Enable-AzVM {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to enable")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that the VM belongs to")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Enable-AzVM is deprecated - consider switching to Start-VM"
    $powerState = (Get-AzVM -Name $Name -ResourceGroupName $ResourceGroupName -Status).Statuses.Code[1]
    if ($powerState -eq "PowerState/running") {
        return Start-VM -Name $Name -ResourceGroupName $ResourceGroupName -ForceRestart
    } else {
        return Start-VM -Name $Name -ResourceGroupName $ResourceGroupName
    }
}
Export-ModuleMember -Function Enable-AzVM


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


# Get image definition from the type specified in the config file
# ---------------------------------------------------------------
function Get-ImageDefinition {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Type of image to retrieve the definition for")]
        [string]$Type
    )
    Add-LogMessage -Level Info "[ ] Getting image type from gallery..."
    if ($Type -eq "Ubuntu") {
        $imageDefinition = "SecureResearchDesktop-Ubuntu"
    } else {
        Add-LogMessage -Level Fatal "Failed to interpret $Type as an image type!"
    }
    Add-LogMessage -Level Success "Interpreted $Type as image type $imageDefinition"
    return $imageDefinition
}
Export-ModuleMember -Function Get-ImageDefinition


# Get NS Records
# --------------
function Get-NSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of record set")]
        [string]$RecordSetName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone")]
        [string]$DnsZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Reading NS records '$($RecordSetName)' for DNS Zone '$($DnsZoneName)'..."
    $recordSet = Get-AzDnsRecordSet -ZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName -Name $RecordSetName -RecordType "NS"
    return $recordSet.Records
}
Export-ModuleMember -Function Get-NSRecords


# Get subnet
# ----------
function Get-Subnet {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of subnet to retrieve")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual network that this subnet belongs to")]
        [string]$VirtualNetworkName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group that this subnet belongs to")]
        [string]$ResourceGroupName
    )
    $virtualNetwork = Get-AzVirtualNetwork -Name $VirtualNetworkName -ResourceGroupName $ResourceGroupName
    return ($virtualNetwork.Subnets | Where-Object { $_.Name -eq $Name })[0]
}
Export-ModuleMember -Function Get-Subnet


# Get the virtual network that a given subnet belongs to
# ------------------------------------------------------
function Get-VirtualNetworkFromSubnet {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Subnet that we want the virtual network for")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet
    )
    $originalContext = Get-AzContext
    $null = Set-AzContext -SubscriptionId $Subnet.Id.Split("/")[2] -ErrorAction Stop
    $virtualNetwork = Get-AzVirtualNetwork | Where-Object { (($_.Subnets | Where-Object { $_.Id -eq $Subnet.Id }).Count -gt 0) }
    $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    return $virtualNetwork
}
Export-ModuleMember -Function Get-VirtualNetworkFromSubnet


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


# Update and reboot a machine
# ---------------------------
function Invoke-WindowsConfiguration {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to run on")]
        [string]$VMName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Time zone to use")]
        [string]$TimeZone,
        [Parameter(Mandatory = $true, HelpMessage = "NTP server to use")]
        [string]$NtpServer,
        [Parameter(Mandatory = $false, HelpMessage = "Additional Powershell modules")]
        [string[]]$AdditionalPowershellModules = @()
    )
    # Install core Powershell modules
    Add-LogMessage -Level Info "[ ] Installing core Powershell modules on '$VMName'"
    $corePowershellScriptPath = Join-Path $PSScriptRoot "remote" "Install_Core_Powershell_Modules.ps1"
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $corePowershellScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName
    # Install additional Powershell modules
    if ($AdditionalPowershellModules) {
        Add-LogMessage -Level Info "[ ] Installing additional Powershell modules on '$VMName'"
        $additionalPowershellScriptPath = Join-Path $PSScriptRoot "remote" "Install_Additional_Powershell_Modules.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $additionalPowershellScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName -Parameter @{"ModuleNamesB64" = ($AdditionalPowershellModules | ConvertTo-Json -Depth 99 | ConvertTo-Base64) }
    }
    # Set locale and run update script
    Add-LogMessage -Level Info "[ ] Setting time/locale and installing updates on '$VMName'"
    $InstallationScriptPath = Join-Path $PSScriptRoot "remote" "Configure_Windows.ps1"
    $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $InstallationScriptPath -VMName $VMName -ResourceGroupName $ResourceGroupName -Parameter @{"TimeZone" = "$TimeZone"; "NTPServer" = "$NtpServer"; "Locale" = "en-GB" }
    # Reboot the VM
    Start-VM -Name $VMName -ResourceGroupName $ResourceGroupName -ForceRestart
}
Export-ModuleMember -Function Invoke-WindowsConfiguration


# Create DNS Zone if it does not exist
# ------------------------------------
function New-DNSZone {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName
    )
    Add-LogMessage -Level Info "Ensuring that DNS zone '$($Name)' exists..."
    $null = Get-AzDnsZone -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating DNS Zone '$Name'"
        $null = New-AzDnsZone -Name $Name -ResourceGroupName $ResourceGroupName
        if ($?) {
            Add-LogMessage -Level Success "Created DNS Zone '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create DNS Zone '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "DNS Zone '$Name' already exists"
    }
}
Export-ModuleMember -Function New-DNSZone


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


# Remove Virtual Machine disk
# ---------------------------
function Remove-VirtualMachineDisk {
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
Export-ModuleMember -Function Remove-VirtualMachineDisk


# Remove a virtual machine NIC
# ----------------------------
function Remove-VirtualMachineNIC {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM NIC to remove")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to remove from")]
        [string]$ResourceGroupName
    )
    $null = Get-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level InfoSuccess "VM network card '$Name' does not exist"
    } else {
        Add-LogMessage -Level Info "[ ] Removing VM network card '$Name'"
        $null = Remove-AzNetworkInterface -Name $Name -ResourceGroupName $ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Removed VM network card '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to remove VM network card '$Name'"
        }
    }
}
Export-ModuleMember -Function Remove-VirtualMachineNIC


# Add NS Record Set to DNS Zone if it does not already exist
# ---------------------------------------------------------
function Set-DnsZoneAndParentNSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone to create")]
        [string]$DnsZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group holding DNS zones")]
        [string]$ResourceGroupName
    )
    # Get subdomain and parent domain
    $subdomain = $DnsZoneName.Split('.')[0]
    $parentDnsZoneName = $DnsZoneName -replace "$subdomain.", ""

    # Create DNS Zone
    New-DNSZone -Name $DnsZoneName -ResourceGroupName $ResourceGroupName

    # Get NS records from the new DNS Zone
    Add-LogMessage -Level Info "Get NS records from the new DNS Zone..."
    $nsRecords = Get-NSRecords -RecordSetName "@" -DnsZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName

    # Check if parent DNS Zone exists in same subscription and resource group
    $null = Get-AzDnsZone -Name $parentDnsZoneName -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "No existing DNS Zone was found for '$parentDnsZoneName' in resource group '$ResourceGroupName'."
        Add-LogMessage -Level Info "You need to add the following NS records to the parent DNS system for '$parentDnsZoneName': '$nsRecords'"
    } else {
        # Add NS records to the parent DNS Zone
        Add-LogMessage -Level Info "Add NS records to the parent DNS Zone..."
        Set-NSRecords -RecordSetName $subdomain -DnsZoneName $parentDnsZoneName -ResourceGroupName $ResourceGroupName -NsRecords $nsRecords
    }
}
Export-ModuleMember -Function Set-DnsZoneAndParentNSRecords


# Set key vault permissions to the group and remove the user who deployed it
# --------------------------------------------------------------------------
function Set-KeyVaultPermissions {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of key vault to set the permissions on")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of group to give permissions to")]
        [string]$GroupName
    )
    Add-LogMessage -Level Info "Giving group '$GroupName' access to key vault '$Name'..."
    try {
        $securityGroupId = (Get-AzADGroup -DisplayName $GroupName).Id | Select-Object -First 1
    } catch [Microsoft.Azure.Commands.ActiveDirectory.GetAzureADGroupCommand] {
        Add-LogMessage -Level Fatal "Could not identify an Azure security group called $GroupName!"
    }
    Set-AzKeyVaultAccessPolicy -VaultName $Name `
                               -ObjectId $securityGroupId `
                               -PermissionsToKeys Get, List, Update, Create, Import, Delete, Backup, Restore, Recover, Purge `
                               -PermissionsToSecrets Get, List, Set, Delete, Recover, Backup, Restore, Purge `
                               -PermissionsToCertificates Get, List, Delete, Create, Import, Update, Managecontacts, Getissuers, Listissuers, Setissuers, Deleteissuers, Manageissuers, Recover, Backup, Restore, Purge `
                               -WarningAction SilentlyContinue
    $success = $?
    foreach ($accessPolicy in (Get-AzKeyVault $Name -WarningAction SilentlyContinue).AccessPolicies | Where-Object { $_.ObjectId -ne $securityGroupId }) {
        Remove-AzKeyVaultAccessPolicy -VaultName $Name -ObjectId $accessPolicy.ObjectId -WarningAction SilentlyContinue
        $success = $success -and $?
    }
    if ($success) {
        Add-LogMessage -Level Success "Set correct access policies for key vault '$Name'"
    } else {
        Add-LogMessage -Level Fatal "Failed to set correct access policies for key vault '$Name'!"
    }
}
Export-ModuleMember -Function Set-KeyVaultPermissions


# Add NS Record Set to DNS Zone if it doesn't already exist
# ---------------------------------------------------------
function Set-NSRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of record set")]
        [string]$RecordSetName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of DNS zone")]
        [string]$DnsZoneName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "NS records to add")]
        $NsRecords
    )
    $null = Get-AzDnsRecordSet -ResourceGroupName $ResourceGroupName -ZoneName $DnsZoneName -Name $RecordSetName -RecordType NS -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "Creating new Record Set '$($RecordSetName)' in DNS Zone '$($DnsZoneName)' with NS records '$($nsRecords)' to ..."
        $null = New-AzDnsRecordSet -Name $RecordSetName –ZoneName $DnsZoneName -ResourceGroupName $ResourceGroupName -Ttl 3600 -RecordType NS -DnsRecords $NsRecords
        if ($?) {
            Add-LogMessage -Level Success "Created DNS Record Set '$RecordSetName'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create DNS Record Set '$RecordSetName'!"
        }
    } else {
        # It's not straightforward to modify existing record sets idempotently so if the set already exists we do nothing
        Add-LogMessage -Level InfoSuccess "DNS record set '$RecordSetName' already exists. Will not update!"
    }
}
Export-ModuleMember -Function Set-NSRecords


# Attach a network security group to a subnet
# -------------------------------------------
function Set-SubnetNetworkSecurityGroup {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Subnet whose NSG will be set")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "Network security group to attach")]
        $NetworkSecurityGroup,
        [Parameter(Mandatory = $false, HelpMessage = "Virtual network that the subnet belongs to")]
        $VirtualNetwork
    )
    if (-not $VirtualNetwork) {
        $VirtualNetwork = Get-VirtualNetworkFromSubnet -Subnet $Subnet
    }
    Add-LogMessage -Level Info "Ensuring that NSG '$($NetworkSecurityGroup.Name)' is attached to subnet '$($Subnet.Name)'..."
    $null = Set-AzVirtualNetworkSubnetConfig -Name $Subnet.Name -VirtualNetwork $VirtualNetwork -AddressPrefix $Subnet.AddressPrefix -NetworkSecurityGroup $NetworkSecurityGroup
    $success = $?
    $VirtualNetwork = Set-AzVirtualNetwork -VirtualNetwork $VirtualNetwork
    $success = $success -and $?
    $updatedSubnet = Get-Subnet -Name $Subnet.Name -VirtualNetworkName $VirtualNetwork.Name -ResourceGroupName $VirtualNetwork.ResourceGroupName
    $success = $success -and $?
    if ($success) {
        Add-LogMessage -Level Success "Set network security group on '$($Subnet.Name)'"
    } else {
        Add-LogMessage -Level Fatal "Failed to set network security group on '$($Subnet.Name)'!"
    }
    return $updatedSubnet
}
Export-ModuleMember -Function Set-SubnetNetworkSecurityGroup


# Ensure Firewall is running, with option to force a restart
# ----------------------------------------------------------
function Start-Firewall {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of Firewall")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Firewall resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Name of virtual network containing the 'AzureFirewall' subnet")]
        [string]$VirtualNetworkName,
        [Parameter(Mandatory = $false, HelpMessage = "Force restart of Firewall")]
        [switch]$ForceRestart
    )
    Add-LogMessage -Level Info "Ensuring that firewall '$Name' is running..."
    $firewall = Get-AzFirewall -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if (-not $firewall) {
        Add-LogMessage -Level Error "Firewall '$Name' does not exist in $ResourceGroupName"
    } else {
        $virtualNetwork = Get-AzVirtualNetwork -Name $VirtualNetworkName
        $publicIP = Get-AzPublicIpAddress -Name "${Name}-PIP" -ResourceGroupName $ResourceGroupName
        if ($ForceRestart) {
            Add-LogMessage -Level Info "Restart requested. Deallocating firewall '$Name'..."
            $firewall = Stop-Firewall -Name $Name -ResourceGroupName $ResourceGroupName
        }
        # At this point we either have a running firewall or a stopped firewall.
        # A firewall is allocated if it has one or more IP configurations.
        if ($firewall.IpConfigurations) {
            Add-LogMessage -Level InfoSuccess "Firewall '$Name' is already running."
        } else {
            try {
                Add-LogMessage -Level Info "[ ] Starting firewall '$Name'..."
                $firewall.Allocate($virtualNetwork, $publicIp)
                $firewall = Set-AzFirewall -AzureFirewall $firewall -ErrorAction Stop
                Add-LogMessage -Level Success "Firewall '$Name' successfully started."
            } catch {
                Add-LogMessage -Level Fatal "Failed to (re)start firewall '$Name'" -Exception $_.Exception
            }
        }
    }
    return $firewall
}
Export-ModuleMember -Function Start-Firewall


# Ensure Firewall is deallocated
# ------------------------------
function Stop-Firewall {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of Firewall")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Name of Firewall resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $false, HelpMessage = "Submit request to stop but don't wait for completion.")]
        [switch]$NoWait
    )
    Add-LogMessage -Level Info "Ensuring that firewall '$Name' is deallocated..."
    $firewall = Get-AzFirewall -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if (-not $firewall) {
        Add-LogMessage -Level Fatal "Firewall '$Name' does not exist."
        Exit 1
    }
    # At this point we either have a running firewall or a stopped firewall.
    # A firewall is allocated if it has one or more IP configurations.
    $firewallAllocacted = ($firewall.IpConfigurations.Length -ge 1)
    if (-not $firewallAllocacted) {
        Add-LogMessage -Level InfoSuccess "Firewall '$Name' is already deallocated."
    } else {
        Add-LogMessage -Level Info "[ ] Deallocating firewall '$Name'..."
        $firewall.Deallocate()
        $firewall = Set-AzFirewall -AzureFirewall $firewall -AsJob:$NoWait -ErrorAction Stop
        if ($NoWait) {
            Add-LogMessage -Level Success "Request to deallocate firewall '$Name' accepted."
        } else {
            Add-LogMessage -Level Success "Firewall '$Name' successfully deallocated."
        }
        $firewall = Get-AzFirewall -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    }
    return $firewall
}
Export-ModuleMember -Function Stop-Firewall


# Update LDAP secret in the local Active Directory
# ------------------------------------------------
function Update-AdLdapSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of DC that holds the local Active Directory")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group for DC that holds the local Active Directory")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subscription name for DC that holds the local Active Directory")]
        [string]$SubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Password for LDAP search account")]
        [string]$LdapSearchPassword,
        [Parameter(Mandatory = $true, HelpMessage = "SAM account name for LDAP search account")]
        [string]$LdapSearchSamAccountName
    )
    # Get original subscription
    $originalContext = Get-AzContext
    try {
        $null = Set-AzContext -SubscriptionId $SubscriptionName -ErrorAction Stop
        Add-LogMessage -Level Info "[ ] Setting LDAP secret in local AD (${Name})"
        $params = @{
            ldapSearchSamAccountName = $LdapSearchSamAccountName
            ldapSearchPasswordB64    = $LdapSearchPassword | ConvertTo-Base64
        }
        $scriptPath = Join-Path $PSScriptRoot "remote" "ResetLdapPasswordOnAD.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $Name -ResourceGroupName $ResourceGroupName -Parameter $params
    } finally {
        # Switch back to original subscription
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
}
Export-ModuleMember -Function Update-AdLdapSecret


# Update LDAP secret for a VM
# ---------------------------
function Update-VMLdapSecret {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "VM name")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "VM resource group")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Password for LDAP search account")]
        [string]$LdapSearchPassword
    )
    Add-LogMessage -Level Info "[ ] Setting LDAP secret on SRD '${Name}'"
    $params = @{
        ldapSearchPasswordB64 = $LdapSearchPassword | ConvertTo-Base64
    }
    $scriptPath = Join-Path $PSScriptRoot "remote" "ResetLdapPasswordOnVm.sh"
    $null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $Name -ResourceGroupName $ResourceGroupName -Parameter $params
}
Export-ModuleMember -Function Update-VMLdapSecret
