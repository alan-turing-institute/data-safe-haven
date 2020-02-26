# You will need `Install-Package Communary.PASM`
param(
    [Parameter(Mandatory = $true, HelpMessage = "Name of the current SHM subscription")]
    [string]$currentShmSubscription,
    [Parameter(Mandatory = $true, HelpMessage = "Name of the new SHM subscription")]
    [string]$newShmSubscription,
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

# Get original context before switching subscription
# --------------------------------------------------
$originalContext = Get-AzContext


# Get VMs in current SHM
# ----------------------
$_ = Set-AzContext -SubscriptionId $currentShmSubscription
$currentShmVMs = Get-AzVM | Where-Object { $_.Name -NotLike "*shm-deploy*" }
Add-LogMessage -Level Info "Found $($currentShmVMs.Count) VMs in current subscription"

# Get VMs in new SHM
# ------------------
$_ = Set-AzContext -SubscriptionId $newShmSubscription
$newShmVMs = Get-AzVM
Add-LogMessage -Level Info "Found $($newShmVMs.Count) VMs in new subscription"


# Create a hash table which maps current SHM VMs to new ones
# ----------------------------------------------------------
$vmHashTable = @{}
$newShmVMNames = $newShmVMs | ForEach-Object { $_.Name }

foreach ($currentVM in $currentShmVMs) {
    $newVM = $newShmVMs | Where-Object { $_.Name -eq $(Select-ClosestMatch -Array $newShmVMNames -Value $currentVM.Name) }
    $vmHashTable[$currentVM] = $newVM
}

# Iterate over paired VMs checking their effective NSG rules
# ----------------------------------------------------------
foreach ($currentVM in $currentShmVMs) {
    $newVM = $vmHashTable[$currentVM]

    # Get existing rules
    $_ = Set-AzContext -SubscriptionId $currentShmSubscription
    $currentEffectiveNSG = Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName ($currentVM.NetworkProfile.NetworkInterfaces.Id -Split '/')[-1] -ResourceGroupName $currentVM.ResourceGroupName
    $currentRules = $currentEffectiveNSG.EffectiveSecurityRules

    # Get new rules
    $_ = Set-AzContext -SubscriptionId $newShmSubscription
    $newEffectiveNSG = Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName ($newVM.NetworkProfile.NetworkInterfaces.Id -Split '/')[-1] -ResourceGroupName $newVM.ResourceGroupName
    $newRules = $newEffectiveNSG.EffectiveSecurityRules

    # Check that each NSG rules has a matching equivalent (which might be named differently)
    Add-LogMessage -Level Info "Comparing NSG rules for $($currentVM.Name) and $($newVM.Name)"
    Add-LogMessage -Level Info "... ensuring that all $($currentVM.Name) rules exist on $($newVM.Name)"
    Compare-NSGRules -CurrentRules $currentRules -NewRules $newRules
    Add-LogMessage -Level Info "... ensuring that all $($newVM.Name) rules exist on $($currentVM.Name)"
    Compare-NSGRules -CurrentRules $newRules -NewRules $currentRules
}



# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
