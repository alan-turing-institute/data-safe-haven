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
