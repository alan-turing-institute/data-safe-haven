# You will need `Install-Package Communary.PASM`
param(
    [Parameter(Mandatory = $true, HelpMessage = "Name of the current (working) subscription")]
    [string]$currentSubscription,
    [Parameter(Mandatory = $true, HelpMessage = "Name of the new (proposed) subscription")]
    [string]$newSubscription,
    [Parameter(Mandatory = $false, HelpMessage = "Print verbose logging messages")]
    [switch]$VerboseLogging = $false
)

Import-Module Az
Import-Module Communary.PASM
Import-Module $PSScriptRoot/../common_powershell/Logging.psm1 -Force

function Select-ClosestMatch {
    param (
        [Parameter(Position = 0)][ValidateNotNullOrEmpty()]
        [string] $Value,
        [Parameter(Position = 1)][ValidateNotNullOrEmpty()]
        [System.Array] $Array
    )
    $Array | Sort-Object @{Expression={ Get-PasmScore -String1 $Value -String2 $_ -Algorithm "LevenshteinDistance" }; Ascending=$false} | Select-Object -First 1
}


function Compare-NSGRules {
    param (
        [Parameter()][ValidateNotNullOrEmpty()]
        [System.Array] $CurrentRules,
        [Parameter()][ValidateNotNullOrEmpty()]
        [System.Array] $NewRules
    )
    $nMatched = 0
    $unmatched = @()
    $matchFound = $false
    foreach ($currentRule in $CurrentRules) {
        foreach ($newRule in $NewRules) {
            if (
                ($currentRule.Protocol -eq $newRule.Protocol) -and
                ([string]($currentRule.SourcePortRange) -eq [string]($newRule.SourcePortRange)) -and
                ([string]($currentRule.DestinationPortRange) -eq [string]($newRule.DestinationPortRange)) -and
                ([string]($currentRule.SourceAddressPrefix) -eq [string]($newRule.SourceAddressPrefix)) -and
                ([string]($currentRule.DestinationAddressPrefix) -eq [string]($newRule.DestinationAddressPrefix)) -and
                ($currentRule.Access -eq $newRule.Access) -and
                ($currentRule.Priority -eq $newRule.Priority) -and
                ($currentRule.Direction -eq $newRule.Direction)
            ) {
                $matchFound = $true
                break
            }
        }

        if ($matchFound) {
            $nMatched += 1
            if ($VerboseLogging) { Add-LogMessage -Level Info "Found matching rule for $($currentRule.Name)" }
        } else {
            Add-LogMessage -Level Error "Could not find matching rule for $($currentRule.Name)"
            $unmatched += $currentRule.Name
        }
    }

    $nTotal = $nMatched + $unmatched.Count
    if ($nMatched -eq $nTotal) {
        Add-LogMessage -Level Success "Matched $nMatched/$nTotal rules"
    } else {
        Add-LogMessage -Level Failure "Matched $nMatched/$nTotal rules"
    }
}


function Test-OutboundConnection {
    param (
        [Parameter(Position = 0)][ValidateNotNullOrEmpty()]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $VM,
        [Parameter(Position = 0)][ValidateNotNullOrEmpty()]
        [string] $DestinationAddress,
        [Parameter(Position = 1)][ValidateNotNullOrEmpty()]
        [string] $DestinationPort
    )
    $networkWatcher = Get-AzNetworkWatcher | Where-Object -Property Location -EQ -Value $VM.Location
    if (-Not $networkWatcher) {
        $networkWatcher = New-AzNetworkWatcher -Name "NetworkWatcher" -ResourceGroupName "NetworkWatcherRG" -Location $VM.Location
    }
    Get-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Name "AzureNetworkWatcherExtension" -ErrorVariable NotInstalled -ErrorAction SilentlyContinue
    if ($NotInstalled) {
        Set-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Location $VM.Location -Name "networkWatcherAgent" -Publisher "Microsoft.Azure.NetworkWatcher" -Type "NetworkWatcherAgentWindows" -TypeHandlerVersion "1.4"
    }
    return Test-AzNetworkWatcherConnectivity -NetworkWatcher $networkWatcher -SourceId $VM.Id -DestinationAddress $DestinationAddress -DestinationPort $DestinationPort
}



# Get original context before switching subscription
# --------------------------------------------------
$originalContext = Get-AzContext


# Get VMs in current SHM
# ----------------------
$_ = Set-AzContext -SubscriptionId $currentSubscription
$currentShmVMs = Get-AzVM | Where-Object { $_.Name -NotLike "*shm-deploy*" }
Add-LogMessage -Level Info "Found $($currentShmVMs.Count) VMs in current subscription: '$currentSubscription'"
foreach ($VM in $currentShmVMs) {
    Add-LogMessage -Level Info ".. $($VM.Name)"
}

# Get VMs in new SHM
# ------------------
$_ = Set-AzContext -SubscriptionId $newSubscription
$newShmVMs = Get-AzVM
Add-LogMessage -Level Info "Found $($newShmVMs.Count) VMs in new subscription: '$newSubscription'"
foreach ($VM in $newShmVMs) {
    Add-LogMessage -Level Info ".. $($VM.Name)"
}

# Create a hash table which maps current SHM VMs to new ones
# ----------------------------------------------------------
$vmHashTable = @{}
$newShmVMNames = $newShmVMs | ForEach-Object { $_.Name }

foreach ($currentVM in $currentShmVMs) {
    $newVM = $newShmVMs | Where-Object { $_.Name -eq $(Select-ClosestMatch -Array $newShmVMNames -Value $currentVM.Name) }
    $vmHashTable[$currentVM] = $newVM
}

# Iterate over paired VMs checking their network settings
# -------------------------------------------------------
foreach ($currentVM in $currentShmVMs) {
    $newVM = $vmHashTable[$currentVM]

    # Get parameters for current VM
    # -----------------------------
    $_ = Set-AzContext -SubscriptionId $currentSubscription
    # NSG rules
    $currentEffectiveNSG = Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName ($currentVM.NetworkProfile.NetworkInterfaces.Id -Split '/')[-1] -ResourceGroupName $currentVM.ResourceGroupName
    $currentRules = $currentEffectiveNSG.EffectiveSecurityRules
    # Internet out
    $currentInternetCheck = Test-OutboundConnection -VM $currentVM -DestinationAddress "google.com" -DestinationPort 80

    # Get parameters for new VM
    # -------------------------
    $_ = Set-AzContext -SubscriptionId $newSubscription
    # NSG rules
    $newEffectiveNSG = Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName ($newVM.NetworkProfile.NetworkInterfaces.Id -Split '/')[-1] -ResourceGroupName $newVM.ResourceGroupName
    $newRules = $newEffectiveNSG.EffectiveSecurityRules
    # Internet out
    $newInternetCheck = Test-OutboundConnection -VM $newVM -DestinationAddress "google.com" -DestinationPort 80

    # Check that each NSG rule has a matching equivalent (which might be named differently)
    Add-LogMessage -Level Info "Comparing NSG rules for $($currentVM.Name) and $($newVM.Name)"
    Add-LogMessage -Level Info "... ensuring that all $($currentVM.Name) rules exist on $($newVM.Name)"
    Compare-NSGRules -CurrentRules $currentRules -NewRules $newRules
    Add-LogMessage -Level Info "... ensuring that all $($newVM.Name) rules exist on $($currentVM.Name)"
    Compare-NSGRules -CurrentRules $newRules -NewRules $currentRules

    # Check that internet connectivity is the same for matched VMs
    Add-LogMessage -Level Info "Comparing internet connectivity for $($currentVM.Name) and $($newVM.Name)..."
    if ($currentInternetCheck.ConnectionStatus -eq $newInternetCheck.ConnectionStatus) {
        Add-LogMessage -Level Success "... the internet is '$($currentInternetCheck.ConnectionStatus)' from both"
    } else {
        Add-LogMessage -Level Failure "... the internet is '$($currentInternetCheck.ConnectionStatus)' from $($currentVM.Name)"
        Add-LogMessage -Level Failure "... the internet is '$($newInternetCheck.ConnectionStatus)' from $($newVM.Name)"
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
