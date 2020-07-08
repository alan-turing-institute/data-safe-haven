<#PSScriptInfo
 
.VERSION 1.7
 
.GUID 76a487ef-47bf-4537-8942-600a66a547b1
 
.AUTHOR dougbrad@microsoft.com
 
.COMPANYNAME
 
.COPYRIGHT
 
.TAGS
 
.LICENSEURI
 
.PROJECTURI
 
.ICONURI
 
.EXTERNALMODULEDEPENDENCIES
 
.REQUIREDSCRIPTS
 
.EXTERNALSCRIPTDEPENDENCIES
 
.RELEASENOTES
 
.PRIVATEDATA
 
#>

<#
.SYNOPSIS
This script installs VM extensions for Log Analytics and Dependency Agent as needed for VM Insights.

Source: https://www.powershellgallery.com/packages/Install-VMInsights/1.7/Content/Install-VMInsights.ps1
 
.DESCRIPTION
This script installs or re-configures following on VM's and VM Scale Sets:
- Log Analytics VM Extension configured to supplied Log Analytics Workspace
- Dependency Agent VM Extension
 
Can be applied to:
- Subscription
- Resource Group in a Subscription
- Specific VM/VM Scale Set
- Compliance results of a policy for a VM or VM Extension
 
Script will show you list of VM's/VM Scale Sets that will apply to and let you confirm to continue.
Use -Approve switch to run without prompting, if all required parameters are provided.
 
If the extensions are already installed will not install again.
Use -ReInstall switch if you need to for example update the workspace.
 
Use -WhatIf if you would like to see what would happen in terms of installs, what workspace configured to, and status of the extension.
 
.PARAMETER WorkspaceId
Log Analytics WorkspaceID (GUID) for the data to be sent to
 
.PARAMETER WorkspaceKey
Log Analytics Workspace primary or secondary key
 
.PARAMETER SubscriptionId
SubscriptionId for the VMs/VM Scale Sets
If using PolicyAssignmentName parameter, subscription that VM's are in
 
.PARAMETER WorkspaceRegion
Region the Log Analytics Workspace is in
Suported values: "East US","eastus","Southeast Asia","southeastasia","West Central US","westcentralus","West Europe","westeurope", "Canada Central", "canadacentral", "UK South", "uksouth", "West US 2", "westus2", "East Australia", "eastaustralia", "Southeast Australia", "southeastaustralia", "Japan East", "japaneast", "North Europe", "northeurope", "East US 2", "eastus2", "South Central US", "southcentralus", "North Central US", "northcentralus", "Central US", "centralus", "West US", "westus", "Central India", "centralindia", "East Asia", "eastasia","East US 2 EUAP", "eastus2euap"
For Health supported is: "East US","eastus","West Central US","westcentralus", "West Europe", "westeurope"
 
.PARAMETER ResourceGroup
<Optional> Resource Group to which the VMs or VM Scale Sets belong to
 
.PARAMETER Name
<Optional> To install to a single VM/VM Scale Set
 
.PARAMETER PolicyAssignmentName
<Optional> Take the input VM's to operate on as the Compliance results from this Assignment
If specified will only take from this source.
 
.PARAMETER ReInstall
<Optional> If VM/VM Scale Set is already configured for a different workspace, set this to change to the new workspace
 
.PARAMETER TriggerVmssManualVMUpdate
<Optional> Set this flag to trigger update of VM instances in a scale set whose upgrade policy is set to Manual
 
.PARAMETER Approve
<Optional> Gives the approval for the installation to start with no confirmation prompt for the listed VM's/VM Scale Sets
 
.PARAMETER Whatif
<Optional> See what would happen in terms of installs.
If extension is already installed will show what workspace is currently configured, and status of the VM extension
 
.PARAMETER Confirm
<Optional> Confirm every action
 
.EXAMPLE
.\Install-VMInsights.ps1 -WorkspaceRegion eastus -WorkspaceId <WorkspaceId> -WorkspaceKey <WorkspaceKey> -SubscriptionId <SubscriptionId> -ResourceGroup <ResourceGroup>
Install for all VM's in a Resource Group in a subscription
 
.EXAMPLE
.\Install-VMInsights.ps1 -WorkspaceRegion eastus -WorkspaceId <WorkspaceId> -WorkspaceKey <WorkspaceKey> -SubscriptionId <SubscriptionId> -ResourceGroup <ResourceGroup> -ReInstall
Specify to ReInstall extensions even if already installed, for example to update to a different workspace
 
.EXAMPLE
.\Install-VMInsights.ps1 -WorkspaceRegion eastus -WorkspaceId <WorkspaceId> -WorkspaceKey <WorkspaceKey> -SubscriptionId <SubscriptionId> -PolicyAssignmentName a4f79f8ce891455198c08736 -ReInstall
Specify to use a PolicyAssignmentName for source, and to ReInstall (move to a new workspace)
 
.LINK
This script is posted to and further documented at the following location:
http://aka.ms/OnBoardVMInsights
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(mandatory = $true)][string]$WorkspaceId,
    [Parameter(mandatory = $true)][string]$WorkspaceKey,
    [Parameter(mandatory = $true)][string]$SubscriptionId,
    [Parameter(mandatory = $false)][string]$ResourceGroup,
    [Parameter(mandatory = $false)][string]$Name,
    [Parameter(mandatory = $false)][string]$PolicyAssignmentName,
    [Parameter(mandatory = $false)][switch]$ReInstall,
    [Parameter(mandatory = $false)][switch]$TriggerVmssManualVMUpdate,
    [Parameter(mandatory = $false)][switch]$Approve,
    [Parameter(mandatory = $true)] `
        [ValidateSet( `
            "East US", "eastus", "Southeast Asia", "southeastasia", "West Central US", "westcentralus", "West Europe", "westeurope", "Canada Central", "canadacentral", "UK South", "uksouth", "West US 2", "westus2", "East Australia", "eastaustralia", "Southeast Australia", "southeastaustralia", "Japan East", "japaneast", "North Europe", "northeurope", "East US 2", "eastus2", "South Central US", "southcentralus", "North Central US", "northcentralus", "Central US", "centralus", "West US", "westus", "Central India", "centralindia", "East Asia", "eastasia","East US 2 EUAP", "eastus2euap")] `
        [string]$WorkspaceRegion
)

# supported regions for Health
$supportedHealthRegions = @("East US", "eastus", "West Central US", "westcentralus", "West Europe", "westeurope", "UK South", "uksouth", "UK West", "ukwest")

#
# FUNCTIONS
#
function Get-VMExtension {
    <#
    .SYNOPSIS
    Return the VM extension of specified ExtensionType
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)][string]$VMName,
        [Parameter(mandatory = $true)][string]$vmResourceGroupName,
        [Parameter(mandatory = $true)][string]$ExtensionType
    )

    $vm = Get-AzVM -Name $VMName -ResourceGroupName $vmResourceGroupName -DisplayHint Expand
    $extensions = $vm.Extensions

    foreach ($extension in $extensions) {
        if ($ExtensionType -eq $extension.VirtualMachineExtensionType) {
            Write-Verbose("$VMName : Extension: $ExtensionType found on VM")
            $extension
            return
        }
    }
    Write-Verbose("$VMName : Extension: $ExtensionType not found on VM")
}

function Install-VMExtension {
    <#
    .SYNOPSIS
    Install VM Extension, handling if already installed
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param
    (
        [Parameter(Mandatory = $true)][string]$VMName,
        [Parameter(mandatory = $true)][string]$VMLocation,
        [Parameter(mandatory = $true)][string]$VMResourceGroupName,
        [Parameter(mandatory = $true)][string]$ExtensionType,
        [Parameter(mandatory = $true)][string]$ExtensionName,
        [Parameter(mandatory = $true)][string]$ExtensionPublisher,
        [Parameter(mandatory = $true)][string]$ExtensionVersion,
        [Parameter(mandatory = $false)][hashtable]$PublicSettings,
        [Parameter(mandatory = $false)][hashtable]$ProtectedSettings,
        [Parameter(mandatory = $false)][boolean]$ReInstall,
        [Parameter(mandatory = $true)][hashtable]$OnboardingStatus
    )
    # Use supplied name unless already deployed, use same name
    $extensionName = $ExtensionName

    $extension = Get-VMExtension -VMName $VMName -VMResourceGroup $VMResourceGroupName -ExtensionType $ExtensionType
    if ($extension) {
        $extensionName = $extension.Name

        # of has Settings - it is LogAnalytics extension
        if ($extension.Settings) {
            if ($extension.Settings.ToString().Contains($PublicSettings.workspaceId)) {
                $message = "$VMName : Extension $ExtensionType already configured for this workspace. Provisioning State: " + $extension.ProvisioningState + " " + $extension.Settings
                $OnboardingStatus.AlreadyOnboarded += $message
                Write-Output($message)
            }
            else {
                if ($ReInstall -ne $true) {
                    $message = "$VMName : Extension $ExtensionType already configured for a different workspace. Run with -ReInstall to move to new workspace. Provisioning State: " + $extension.ProvisioningState + " " + $extension.Settings
                    Write-Warning($message)
                    $OnboardingStatus.DifferentWorkspace += $message
                }
            }
        }
        else {
            $message = "$VMName : $ExtensionType extension with name " + $extension.Name + " already installed. Provisioning State: " + $extension.ProvisioningState + " " + $extension.Settings
            Write-Output($message)
        }
    }

    if ($PSCmdlet.ShouldProcess($VMName, "install extension $ExtensionType") -and ($ReInstall -eq $true -or !$extension)) {

        $parameters = @{
            ResourceGroupName  = $VMResourceGroupName
            VMName             = $VMName
            Location           = $VMLocation
            Publisher          = $ExtensionPublisher
            ExtensionType      = $ExtensionType
            ExtensionName      = $extensionName
            TypeHandlerVersion = $ExtensionVersion
        }

        if ($PublicSettings -and $ProtectedSettings) {
            $parameters.Add("Settings", $PublicSettings)
            $parameters.Add("ProtectedSettings", $ProtectedSettings)
        }

        if ($ExtensionType -eq "OmsAgentForLinux") {
            Write-Output("$VMName : ExtensionType: $ExtensionType does not support updating workspace. Uninstalling and Re-Installing")
            $removeResult = Remove-AzVMExtension -ResourceGroupName $VMResourceGroupName -VMName $VMName -Name $extensionName -Force

            if ($removeResult -and $removeResult.IsSuccessStatusCode) {
                $message = "$VMName : Successfully removed $ExtensionType"
                Write-Output($message)
            }
            else {
                $message = "$VMName : Failed to remove $ExtensionType (for $ExtensionType need to remove and re-install if changing workspace with -ReInstall)"
                Write-Warning($message)
                $OnboardingStatus.Failed += $message
            }
        }

        Write-Output("$VMName : Deploying $ExtensionType with name $extensionName")
        $result = Set-AzVMExtension @parameters

        if ($result -and $result.IsSuccessStatusCode) {
            $message = "$VMName : Successfully deployed $ExtensionType"
            Write-Output($message)
            $OnboardingStatus.Succeeded += $message
        }
        else {
            $message = "$VMName : Failed to deploy $ExtensionType"
            Write-Warning($message)
            $OnboardingStatus.Failed += $message
        }
    }
}

function Get-VMssExtension {
    <#
    .SYNOPSIS
    Return the VM extension of specified ExtensionType
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $True)][System.Object]$VMss,
        [Parameter(mandatory = $true)][string]$ExtensionType
    )
    foreach ($extension in $VMss.VirtualMachineProfile.ExtensionProfile.Extensions) {
        if ($ExtensionType -eq $extension.Type) {
            Write-Verbose("$VMScaleSetName : Extension: $ExtensionType found on VMSS")
            $extension
            return
        }
    }
    Write-Verbose("$VMScaleSetName : Extension: $ExtensionType not found on VMSS")
}

function Install-VMssExtension {
    <#
    .SYNOPSIS
    Install VM Extension, handling if already installed
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param
    (
        [Parameter(Mandatory = $True)][string]$VMScaleSetName,
        [Parameter(Mandatory = $True)][string]$VMScaleSetResourceGroupName,
        [Parameter(Mandatory = $True)][string]$ExtensionType,
        [Parameter(Mandatory = $True)][string]$ExtensionName,
        [Parameter(Mandatory = $True)][string]$ExtensionPublisher,
        [Parameter(Mandatory = $True)][string]$ExtensionVersion,
        [Parameter(mandatory = $false)][hashtable]$PublicSettings,
        [Parameter(mandatory = $false)][hashtable]$ProtectedSettings,
        [Parameter(mandatory = $false)][boolean]$ReInstall = $false
    )
    # Use supplied name unless already deployed, use same name
    $extensionName = $ExtensionName

    $scalesetObject = Get-AzVMSS -VMScaleSetName $VMScaleSetName -ResourceGroupName $VMScaleSetResourceGroupName

    $extension = Get-VMssExtension -VMss $scalesetObject -ExtensionType $ExtensionType
    if ($extension) {
        Write-Output("$VMScaleSetName : $ExtensionType extension with name " + $extension.Name + " already installed. Provisioning State: " + $extension.ProvisioningState + " " + $extension.Settings)
        $extensionName = $extension.Name
    }

    if (($ReInstall -eq $true -or !$extension) -and $PSCmdlet.ShouldProcess($VMScaleSetName, "install extension $ExtensionType")) {

        $parameters = @{
            VirtualMachineScaleSet  = $scalesetObject
            Name                    = $extensionName
            Publisher               = $ExtensionPublisher
            Type                    = $ExtensionType
            TypeHandlerVersion      = $ExtensionVersion
            AutoUpgradeMinorVersion = $true
        }

        if ($PublicSettings -and $ProtectedSettings) {
            $parameters.Add("Setting", $PublicSettings)
            $parameters.Add("ProtectedSetting", $ProtectedSettings)
        }

        Write-Verbose("$VMScaleSetName : Adding $ExtensionType with name $extensionName")
        $scalesetObject = Add-AzVmssExtension @parameters

        Write-Output("$VMScaleSetName Updating scale set with $ExtensionType extension")
        $result = Update-AzVmss -VMScaleSetName $VMScaleSetName -ResourceGroupName $VMScaleSetResourceGroupName -VirtualMachineScaleSet $scalesetObject
        if ($result -and $result.ProvisioningState -eq "Succeeded") {
            $message = "$VMScaleSetName : Successfully updated scale set with $ExtensionType extension"
            Write-Output($message)
            $OnboardingStatus.Succeeded += $message
        }
        else {
            $message = "$VMScaleSetName : failed updating scale set with $ExtensionType extension"
            Write-Warning($message)
            $OnboardingStatus.Failed += $message
        }
    }
}

#
# Main Script
#

#
# First make sure authenticed and Select the subscription supplied
#
$account = Get-AzContext
if ($null -eq $account.Account) {
    Write-Output("Account Context not found, please login")
    Login-AzAccount -subscriptionid $SubscriptionId
}
else {
    if ($account.Subscription.Id -eq $SubscriptionId) {
        Write-Verbose("Subscription: $SubscriptionId is already selected.")
        $account
    }
    else {
        Write-Output("Current Subscription:")
        $account
        Write-Output("Changing to subscription: $SubscriptionId")
        Select-AzSubscription -SubscriptionId $SubscriptionId
    }
}

$VMs = @()
$ScaleSets = @()

# To report on overall status
$AlreadyOnboarded = @()
$OnboardingSucceeded = @()
$OnboardingFailed = @()
$OnboardingBlockedNotRunning = @()
$OnboardingBlockedDifferentWorkspace = @()
$VMScaleSetNeedsUpdate = @()
$OnboardingStatus = @{
    AlreadyOnboarded      = $AlreadyOnboarded;
    Succeeded             = $OnboardingSucceeded;
    Failed                = $OnboardingFailed;
    NotRunning            = $OnboardingBlockedNotRunning;
    DifferentWorkspace    = $OnboardingBlockedDifferentWorkspace;
    VMScaleSetNeedsUpdate = $VMScaleSetNeedsUpdate;
}

# Log Analytics Extension constants
$MMAExtensionMap = @{ "Windows" = "MicrosoftMonitoringAgent"; "Linux" = "OmsAgentForLinux" }
$MMAExtensionVersionMap = @{ "Windows" = "1.0"; "Linux" = "1.6" }
$MMAExtensionPublisher = "Microsoft.EnterpriseCloud.Monitoring"
$MMAExtensionName = "MMAExtension"
$PublicSettings = @{"workspaceId" = $WorkspaceId; "stopOnMultipleConnections" = "true"}
$ProtectedSettings = @{"workspaceKey" = $WorkspaceKey}

# Dependency Agent Extension constants
$DAExtensionMap = @{ "Windows" = "DependencyAgentWindows"; "Linux" = "DependencyAgentLinux" }
$DAExtensionVersionMap = @{ "Windows" = "9.5"; "Linux" = "9.5" }
$DAExtensionPublisher = "Microsoft.Azure.Monitoring.DependencyAgent"
$DAExtensionName = "DAExtension"

if ($PolicyAssignmentName) {
    Write-Output("Getting list of VM's from PolicyAssignmentName: " + $PolicyAssignmentName)
    $complianceResults = Get-AzPolicyState -PolicyAssignmentName $PolicyAssignmentName

    foreach ($result in $complianceResults) {
        Write-Verbose($result.ResourceId)
        Write-Verbose($result.ResourceType)
        if ($result.SubscriptionId -ne $SubscriptionId) {
            Write-Output("VM is not in same subscription, this scenario is not currently supported. Skipping this VM.")
        }

        $vmName = $result.ResourceId.split('/')[8]
        $vmResourceGroup = $result.ResourceId.split('/')[4]

        # Skip if ResourceGroup or Name provided, but does not match
        if ($ResourceGroup -and $ResourceGroup -ne $vmResourceGroup) { continue }
        if ($Name -and $Name -ne $vmName) { continue }

        $vm = Get-AzVM -Name $vmName -ResourceGroupName $vmResourceGroup
        $vmStatus = Get-AzVM -Status -Name $vmName -ResourceGroupName $vmResourceGroup

        # fix to have same property as VM that is retrieved without Name
        $vm | Add-Member -NotePropertyName PowerState -NotePropertyValue $vmStatus.Statuses[1].DisplayStatus

        $VMs = @($VMs) + $vm
    }
}

if (! $PolicyAssignmentName) {
    Write-Output("Getting list of VM's or VM ScaleSets matching criteria specified")
    if (!$ResourceGroup -and !$Name) {
        # If ResourceGroup value is not passed - get all VMs under given SubscriptionId
        $VMs = Get-AzVM -Status
        $ScaleSets = Get-AzVmss
        $VMs = @($VMs) + $ScaleSets
    }
    else {
        # If ResourceGroup value is passed - select all VMs under given ResourceGroupName
        $VMs = Get-AzVM -ResourceGroupName $ResourceGroup -Status
        if ($Name) {
            $VMs = $VMs | Where-Object {$_.Name -like $Name}
        }
        $ScaleSets = Get-AzVmss -ResourceGroupName $ResourceGroup
        if ($Name) {
            $ScaleSets = $ScaleSets | Where-Object {$_.Name -like $Name}
        }
        $VMs = @($VMs) + $ScaleSets
    }
}

Write-Output("`nVM's or VM ScaleSets matching criteria:`n")
$VMS | ForEach-Object { Write-Output ($_.Name + " " + $_.PowerState) }

# Validate customer wants to continue
Write-Output("`nThis operation will install the Log Analytics and Dependency Agent extensions on above $($VMS.Count) VM's or VM Scale Sets.")
Write-Output("VM's in a non-running state will be skipped.")
Write-Output("Extension will not be re-installed if already installed. Use -ReInstall if desired, for example to update workspace ")
if ($Approve -eq $true -or !$PSCmdlet.ShouldProcess("All") -or $PSCmdlet.ShouldContinue("Continue?", "")) {
    Write-Output ""
}
else {
    Write-Output "You selected No - exiting"
    return
}

Write-Output "Register the Resource Provider Microsoft.AlertsManagement for Health feature"
Register-AzResourceProvider -ProviderNamespace Microsoft.AlertsManagement

#
# Loop through each VM/VM Scale set, as appropriate handle installing VM Extensions
#
Foreach ($vm in $VMs) {
    # set as variabels so easier to use in output strings
    $vmName = $vm.Name
    $vmLocation = $vm.Location
    $vmResourceGroupName = $vm.ResourceGroupName

    #
    # Find OS Type
    #
    if ($vm.type -eq 'Microsoft.Compute/virtualMachineScaleSets') {
        $isScaleset = $true

        $scalesetVMs = @()
        $scalesetVMs = Get-AzVMssVM -ResourceGroupName $vmResourceGroupName -VMScaleSetName $vmName
        if ($scalesetVMs.length -gt 0) {
            if ($scalesetVMs[0]) {
                $osType = $scalesetVMs[0].storageprofile.osdisk.ostype
            }
        }
    }
    else {
        $isScaleset = $false
        $osType = $vm.StorageProfile.OsDisk.OsType
    }

    #
    # Map to correct extension for OS type
    #
    $mmaExt = $MMAExtensionMap.($osType.ToString())
    if (! $mmaExt) {
        Write-Warning("$vmName : has an unsupported OS: $osType")
        continue
    }
    $mmaExtVersion = $MMAExtensionVersionMap.($osType.ToString())
    $daExt = $DAExtensionMap.($osType.ToString())
    $daExtVersion = $DAExtensionVersionMap.($osType.ToString())

    Write-Verbose("Deployment settings: ")
    Write-Verbose("ResourceGroup: $vmResourceGroupName")
    Write-Verbose("VM: $vmName")
    Write-Verbose("Location: $vmLocation")
    Write-Verbose("OS Type: $ext")
    Write-Verbose("Dependency Agent: $daExt, HandlerVersion: $daExtVersion")
    Write-Verbose("Monitoring Agent: $mmaExt, HandlerVersion: $mmaExtVersion")

    if ($isScaleset) {

        Install-VMssExtension `
            -VMScaleSetName $vmName `
            -VMScaleSetResourceGroupName $vmResourceGroupName `
            -ExtensionType $mmaExt `
            -ExtensionName $mmaExtensionName `
            -ExtensionPublisher $MMAExtensionPublisher `
            -ExtensionVersion $mmaExtVersion `
            -PublicSettings $PublicSettings `
            -ProtectedSettings $ProtectedSettings `
            -ReInstall $ReInstall

        Install-VMssExtension `
            -VMScaleSetName $vmName `
            -VMScaleSetResourceGroupName $vmResourceGroupName `
            -ExtensionType $daExt `
            -ExtensionName $daExtensionName `
            -ExtensionPublisher $DAExtensionPublisher `
            -ExtensionVersion $daExtVersion `
            -ReInstall $ReInstall

        $scalesetObject = Get-AzVMSS -VMScaleSetName $vmName -ResourceGroupName $vmResourceGroupName
        if ($scalesetObject.UpgradePolicy.mode -eq 'Manual') {
            if ($TriggerVmssManualVMUpdate -eq $true) {

                Write-Output("$vmName : Upgrading scale set instances since the upgrade policy is set to Manual")
                $scaleSetInstances = @{}
                $scaleSetInstances = Get-AzVMSSvm -ResourceGroupName $vmResourceGroupName -VMScaleSetName $vmName -InstanceView
                $i = 0
                $instanceCount = $scaleSetInstances.Length
                Foreach ($scaleSetInstance in $scaleSetInstances) {
                    $i++
                    Write-Output("$vmName : Updating instance " + $scaleSetInstance.Name + " $i of $instanceCount")
                    Update-AzVmssInstance -ResourceGroupName $vmResourceGroupName -VMScaleSetName $vmName -InstanceId $scaleSetInstance.InstanceId
                }
                Write-Output("$vmName All scale set instances upgraded")
            }
            else {
                $message = "$vmName : has UpgradePolicy of Manual. Please trigger upgrade of VM Scale Set or call with -TriggerVmssManualVMUpdate"
                Write-Warning($message)
                $OnboardingStatus.VMScaleSetNeedsUpdate += $message
            }
        }
    }
    #
    # Handle VM's
    #
    else {
        if ("VM Running" -ne $vm.PowerState) {
            $message = "$vmName : has a PowerState " + $vm.PowerState + " Skipping"
            Write-Output($message)
            $OnboardingStatus.NotRunning += $message
            continue
        }

        if (!($supportedHealthRegions -contains $WorkspaceRegion)) {
            $message = "$vmname cannot be onboarded to Health monitoring, workspace associated to this is not in a supported region "
            Write-Warning($message)
        }

        Install-VMExtension `
            -VMName $vmName `
            -VMLocation $vmLocation `
            -VMResourceGroupName $vmResourceGroupName `
            -ExtensionType $mmaExt `
            -ExtensionName $mmaExtensionName `
            -ExtensionPublisher $MMAExtensionPublisher `
            -ExtensionVersion $mmaExtVersion `
            -PublicSettings $PublicSettings `
            -ProtectedSettings $ProtectedSettings `
            -ReInstall $ReInstall `
            -OnboardingStatus $OnboardingStatus

        Install-VMExtension `
            -VMName $vmName `
            -VMLocation $vmLocation `
            -VMResourceGroupName $vmResourceGroupName `
            -ExtensionType $daExt `
            -ExtensionName $daExtensionName `
            -ExtensionPublisher $DAExtensionPublisher `
            -ExtensionVersion $daExtVersion `
            -ReInstall $ReInstall `
            -OnboardingStatus $OnboardingStatus

        Write-Output("`n")

    }
}

Write-Output("`nSummary:")
Write-Output("`nAlready Onboarded: (" + $OnboardingStatus.AlreadyOnboarded.Count + ")")
$OnboardingStatus.AlreadyOnboarded  | ForEach-Object { Write-Output ($_) }
Write-Output("`nSucceeded: (" + $OnboardingStatus.Succeeded.Count + ")")
$OnboardingStatus.Succeeded | ForEach-Object { Write-Output ($_) }
Write-Output("`nConnected to different workspace: (" + $OnboardingStatus.DifferentWorkspace.Count + ")")
$OnboardingStatus.DifferentWorkspace | ForEach-Object { Write-Output ($_) }
Write-Output("`nNot running - start VM to configure: (" + $OnboardingStatus.NotRunning.Count + ")")
$OnboardingStatus.NotRunning  | ForEach-Object { Write-Output ($_) }
Write-Output("`nVM Scale Set needs update: (" + $OnboardingStatus.VMScaleSetNeedsUpdate.Count + ")")
$OnboardingStatus.VMScaleSetNeedsUpdate  | ForEach-Object { Write-Output ($_) }
Write-Output("`nFailed: (" + $OnboardingStatus.Failed.Count + ")")
$OnboardingStatus.Failed | ForEach-Object { Write-Output ($_) }