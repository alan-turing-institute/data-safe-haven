# Parameter sets in Powershell are a bit counter-intuitive. See here (https://docs.microsoft.com/en-us/powershell/scripting/developer/cmdlet/cmdlet-parameter-sets?view=powershell-7) for details
param(
    [Parameter(Mandatory = $true, HelpMessage = "Name of the test (proposed) subscription")]
    [string]$Subscription,
    [Parameter(ParameterSetName="BenchmarkSubscription", Mandatory = $true, HelpMessage = "Name of the benchmark subscription to compare against")]
    [string]$BenchmarkSubscription,
    [Parameter(ParameterSetName="BenchmarkConfig", Mandatory = $true, HelpMessage = "Path to the benchmark config to compare against")]
    [string]$BenchmarkConfig,
    [Parameter(Mandatory = $false, HelpMessage = "Print verbose logging messages")]
    [switch]$VerboseLogging = $false
)

# Install required modules
if (-Not $(Get-Module -ListAvailable -Name Az)) { Install-Package Az -Force}
if (-Not $(Get-Module -ListAvailable -Name Communary.PASM)) { Install-Package Communary.PASM -Force}

# Import modules
Import-Module Az -ErrorAction Stop
Import-Module Communary.PASM -ErrorAction Stop
Import-Module $PSScriptRoot/../deployment/common/Logging -Force -ErrorAction Stop

function Select-ClosestMatch {
    param (
        [Parameter(Position = 0)][ValidateNotNullOrEmpty()]
        [string] $Value,
        [Parameter(Position = 1)][ValidateNotNullOrEmpty()]
        [System.Array] $Array
    )
    $Array | Sort-Object @{Expression={ Get-PasmScore -String1 $Value -String2 $_ -Algorithm "LevenshteinDistance" }; Ascending=$false} | Select-Object -First 1
}

# Compare two NSG rule sets
# Match parameter-by-parameter
# --------------------------------------------
function Compare-NSGRules {
    param (
        [Parameter()]
        [System.Array] $BenchmarkRules,
        [Parameter()]
        [System.Array] $TestRules
    )
    $nMatched = 0
    $unmatched = @()
    foreach ($benchmarkRule in $BenchmarkRules) {
        $lowestDifference = [double]::PositiveInfinity
        $closestMatchingRule = $null
        # Iterate over TestRules checking for an identical match by checking how many of the rule parameters differ
        # If an exact match is found then increment the counter, otherwise log the rule and the closest match
        foreach ($testRule in $TestRules) {
            $difference = 0
            if ($benchmarkRule.Protocol -ne $testRule.Protocol) { $difference += 1 }
            if ([string]($benchmarkRule.SourcePortRange) -ne [string]($testRule.SourcePortRange)) { $difference += 1 }
            if ([string]($benchmarkRule.DestinationPortRange) -ne [string]($testRule.DestinationPortRange)) { $difference += 1 }
            if ([string]($benchmarkRule.SourceAddressPrefix) -ne [string]($testRule.SourceAddressPrefix)) { $difference += 1 }
            if ([string]($benchmarkRule.DestinationAddressPrefix) -ne [string]($testRule.DestinationAddressPrefix)) { $difference += 1 }
            if ($benchmarkRule.Access -ne $testRule.Access) { $difference += 1 }
            if ($benchmarkRule.Priority -ne $testRule.Priority) { $difference += 1 }
            if ($benchmarkRule.Direction -ne $testRule.Direction) { $difference += 1 }
            if ($difference -lt $lowestDifference) {
                $lowestDifference = $difference
                $closestMatchingRule = $testRule
            }
            if ($difference -eq 0) { break }
        }

        if ($lowestDifference -eq 0) {
            $nMatched += 1
            if ($VerboseLogging) { Add-LogMessage -Level Info "Found matching rule for $($benchmarkRule.Name)" }
        } else {
            Add-LogMessage -Level Error "Could not find an identical rule for $($benchmarkRule.Name)"
            $unmatched += $benchmarkRule.Name
            $benchmarkRule | Out-String
            Add-LogMessage -Level Info "Closest match was:"
            $closestMatchingRule | Out-String
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
    # Get the network watcher, creating a new one if required
    $networkWatcher = Get-AzNetworkWatcher | Where-Object { $_.Location -eq $VM.Location }
    if (-Not $networkWatcher) {
        $networkWatcher = New-AzNetworkWatcher -Name "NetworkWatcher" -ResourceGroupName "NetworkWatcherRG" -Location $VM.Location
    }
    # Ensure that the VM has the extension installed (if we have permissions for this)
    $networkWatcherExtension = Get-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name | Where-Object { ($_.Publisher -eq "Microsoft.Azure.NetworkWatcher") -and ($_.ProvisioningState -eq "Succeeded") }
    if (-Not $networkWatcherExtension) {
        Add-LogMessage -Level Info "... registering the Azure NetworkWatcher extension on $($VM.Name). "
        # Add the Windows extension
        if ($VM.OSProfile.WindowsConfiguration) {
            $null = Set-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Location $VM.Location -Name "AzureNetworkWatcherExtension" -Publisher "Microsoft.Azure.NetworkWatcher" -Type "NetworkWatcherAgentWindows" -TypeHandlerVersion "1.4" -ErrorVariable NotInstalled -ErrorAction SilentlyContinue
            if ($NotInstalled) {
                Add-LogMessage -Level Warning "Unable to register Windows network watcher extension for $($VM.Name)"
                return "Unknown"
            }
        }
        # Add the Linux extension
        if ($VM.OSProfile.LinuxConfiguration) {
            $null = Set-AzVMExtension -ResourceGroupName $VM.ResourceGroupName -VMName $VM.Name -Location $VM.Location -Name "AzureNetworkWatcherExtension" -Publisher "Microsoft.Azure.NetworkWatcher" -Type "NetworkWatcherAgentLinux" -TypeHandlerVersion "1.4" -ErrorVariable NotInstalled -ErrorAction SilentlyContinue
            if ($NotInstalled) {
                Add-LogMessage -Level Warning "Unable to register Linux network watcher extension for $($VM.Name)"
                return "Unknown"
            }
        }
    }
    Add-LogMessage -Level Info "... testing connectivity on port $DestinationPort"
    $networkCheck = Test-AzNetworkWatcherConnectivity -NetworkWatcher $networkWatcher -SourceId $VM.Id -DestinationAddress $DestinationAddress -DestinationPort $DestinationPort -ErrorVariable NotAvailable -ErrorAction SilentlyContinue
    if ($NotAvailable) {
        Add-LogMessage -Level Warning "Unable to test connection for $($VM.Name)"
        return "Unknown"
    } else {
        return $networkCheck.ConnectionStatus
    }
}

function Convert-RuleToEffectiveRule {
    param (
        [Parameter(Position = 0)][ValidateNotNullOrEmpty()]
        [System.Object] $rule
    )
    $effectiveRule = [Microsoft.Azure.Commands.Network.Models.PSEffectiveSecurityRule]::new()
    $effectiveRule.Name = $rule.Name
    $effectiveRule.Protocol = $rule.Protocol.Replace("*", "All")
    # Source port range
    $effectiveRule.SourcePortRange = New-Object System.Collections.Generic.List[string]
    foreach ($port in $rule.SourcePortRange) {
        # We do not explicitly deal with the case where the port is not an integer, a range or '*'
        if ($port -eq "*") { $effectiveRule.SourcePortRange.Add("0-65535"); break }
        elseif ($port.Contains("-")) { $effectiveRule.SourcePortRange.Add($port) }
        else { $effectiveRule.SourcePortRange.Add("$port-$port") }
    }
    # Destination port range
    $effectiveRule.DestinationPortRange = New-Object System.Collections.Generic.List[string]
    foreach ($port in $rule.DestinationPortRange) {
        # We do not explicitly deal with the case where the port is not an integer, a range or '*'
        if ($port -eq "*") { $effectiveRule.DestinationPortRange.Add("0-65535"); break }
        elseif ($port.Contains("-")) { $effectiveRule.DestinationPortRange.Add($port) }
        else { $effectiveRule.DestinationPortRange.Add("$port-$port") }
    }
    # Source address prefix
    $effectiveRule.SourceAddressPrefix = New-Object System.Collections.Generic.List[string]
    foreach ($prefix in $rule.SourceAddressPrefix) {
        if ($prefix -eq "0.0.0.0/0") { $effectiveRule.SourceAddressPrefix.Add("*"); break }
        else { $effectiveRule.SourceAddressPrefix.Add($rule.SourceAddressPrefix) }
    }
    # Destination address prefix
    $effectiveRule.DestinationAddressPrefix = New-Object System.Collections.Generic.List[string]
    foreach ($prefix in $rule.DestinationAddressPrefix) {
        if ($prefix -eq "0.0.0.0/0") { $effectiveRule.DestinationAddressPrefix.Add("*"); break }
        else { $effectiveRule.DestinationAddressPrefix.Add($rule.DestinationAddressPrefix) }
    }
    $effectiveRule.Access = $rule.Access
    $effectiveRule.Priority = $rule.Priority
    $effectiveRule.Direction = $rule.Direction
    return $effectiveRule
}


function Get-NSGRules {
    param (
        [Parameter(Position = 0)][ValidateNotNullOrEmpty()]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] $VM
    )
    $effectiveNSG = Get-AzEffectiveNetworkSecurityGroup -NetworkInterfaceName ($VM.NetworkProfile.NetworkInterfaces.Id -Split '/')[-1] -ResourceGroupName $VM.ResourceGroupName -ErrorVariable NotAvailable -ErrorAction SilentlyContinue
    if ($NotAvailable) {
        # Not able to get effective rules so we'll construct them by hand
        $rules = @()
        # Get rules from NSG directly attached to the NIC
        $nic = Get-AzNetworkInterface | Where-Object { $_.Id -eq $VM.NetworkProfile.NetworkInterfaces.Id }
        $directNsgs = Get-AzNetworkSecurityGroup | Where-Object { $_.Id -eq $nic.NetworkSecurityGroup.Id }
        $directNsgRules = @()
        foreach ($directNsg in $directNsgs) {
            $directNsgRules = $directNsgRules + $directNsg.SecurityRules + $directNsg.DefaultSecurityRules
        }
        # Get rules from NSG attached to the subnet
        $subnetNsgs = Get-AzNetworkSecurityGroup | Where-Object { $_.Subnets.Id -eq $nic.IpConfigurations.Subnet.Id }
        $subnetNsgRules = @()
        foreach ($subnetNsg in $subnetNsgs) {
            $subnetNsgRules = $subnetNsgRules + $subnetNsg.SecurityRules + $subnetNsg.DefaultSecurityRules
        }
        $effectiveRules = @()
        if ($directNsgRules.Count -And $subnetNsgRules.Count) {
            Add-LogMessage -Level Warning "Found both NSG rules from both the NIC and the subnet for $($VM.Name). Evaluation of effective rules may be incorrect!"
        }
        # Convert each PSSecurityRule into a PSEffectiveSecurityRule
        foreach ($rule in ($directNsgRules + $subnetNsgRules)) {
            $effectiveRules = $effectiveRules + $(Convert-RuleToEffectiveRule $rule)
        }
        return $effectiveRules
    } else {
        $effectiveRules = $effectiveNSG.EffectiveSecurityRules
        # Sometimes the address prefix is retrieved as ("0.0.0.0/0", "0.0.0.0/0") rather than "*" (although these mean the same thing)
        foreach ($effectiveRule in $effectiveRules) {
            if ($effectiveRule.SourceAddressPrefix[0] -eq "0.0.0.0/0") { $effectiveRule.SourceAddressPrefix.Clear(); $effectiveRule.SourceAddressPrefix.Add("*") }
            if ($effectiveRule.DestinationAddressPrefix[0] -eq "0.0.0.0/0") { $effectiveRule.DestinationAddressPrefix.Clear(); $effectiveRule.DestinationAddressPrefix.Add("*") }
        }
        return $effectiveRules
    }
}

# Get original context before switching subscription
# --------------------------------------------------
$originalContext = Get-AzContext


# Load configuration from a benchmark subscription or config
# ----------------------------------------------------------
if ($BenchmarkSubscription) {
    $JsonConfig = [ordered]@{}
    # Get VMs in current subscription
    $null = Set-AzContext -SubscriptionId $BenchmarkSubscription
    $benchmarkVMs = Get-AzVM | Where-Object { $_.Name -NotLike "*shm-deploy*" }
    Add-LogMessage -Level Info "Found $($benchmarkVMs.Count) VMs in subscription: '$BenchmarkSubscription'"
    foreach ($VM in $benchmarkVMs) {
        Add-LogMessage -Level Info "... $($VM.Name)"
    }
    # Get the NSG rules and connectivity for each VM in the subscription
    foreach ($benchmarkVM in $benchmarkVMs) {
        Add-LogMessage -Level Info "Getting NSG rules and connectivity for $($VM.Name)"
        $JsonConfig[$benchmarkVM.Name] = [ordered]@{
            InternetFromPort = [ordered]@{
                "80" = (Test-OutboundConnection -VM $benchmarkVM -DestinationAddress "google.com" -DestinationPort 80)
                "443" = (Test-OutboundConnection -VM $benchmarkVM -DestinationAddress "google.com" -DestinationPort 443)
            }
            Rules = Get-NSGRules -VM $benchmarkVM
        }
    }
    $OutputFile = New-TemporaryFile
    Out-File -FilePath $OutputFile -Encoding "UTF8" -InputObject ($JsonConfig | ConvertTo-Json -Depth 10)
    Add-LogMessage -Level Info "Configuration file generated at '$($OutputFile.FullName)'"
    $BenchmarkJsonPath = $OutputFile.FullName
} elseif ($BenchmarkConfig) {
    $BenchmarkJsonPath = $BenchmarkConfig
}


# Deserialise VMs from JSON config
# --------------------------------
$BenchmarkJsonConfig = Get-Content -Path $BenchmarkJsonPath -Raw -Encoding UTF-8 | ConvertFrom-Json
$benchmarkVMs = @()
foreach ($JsonVm in $BenchmarkJsonConfig.PSObject.Properties) {
    $VM = New-Object -TypeName PsObject
    $VM | Add-Member -MemberType NoteProperty -Name Name -Value $JsonVm.Name
    $VM | Add-Member -MemberType NoteProperty -Name InternetFromPort -Value @{}
    $VM.InternetFromPort.80 = $JsonVm.PSObject.Properties.Value.InternetFromPort.80
    $VM.InternetFromPort.443 = $JsonVm.PSObject.Properties.Value.InternetFromPort.443
    $VM | Add-Member -MemberType NoteProperty -Name Rules -Value @()
    foreach ($rule in $JsonVm.PSObject.Properties.Value.Rules) {
        if ($rule.Name) { $VM.Rules += $(Convert-RuleToEffectiveRule $rule) }
    }
    $benchmarkVMs += $VM
}


# Get VMs in test SHM
# -------------------
$null = Set-AzContext -SubscriptionId $Subscription
$testVMs = Get-AzVM
Add-LogMessage -Level Info "Found $($testVMs.Count) VMs in subscription: '$Subscription'"
foreach ($VM in $testVMs) {
    Add-LogMessage -Level Info "... $($VM.Name)"
}


# Create a hash table which maps test VMs to benchmark ones
# ---------------------------------------------------------
$vmHashTable = @{}
foreach ($testVM in $testVMs) {
    $nameToCheck = $testVM.Name
    # Only match against names that have not been matched yet
    $benchmarkVMNames = $benchmarkVMs | ForEach-Object { $_.Name } | Where-Object { ($vmHashTable.Values | ForEach-Object { $_.Name }) -NotContains $_ }
    $benchmarkVM = $benchmarkVMs | Where-Object { $_.Name -eq $(Select-ClosestMatch -Array $benchmarkVMNames -Value $nameToCheck) }
    $vmHashTable[$testVM] = $benchmarkVM
    Add-LogMessage -Level Info "matched $($testVM.Name) => $($benchmarkVM.Name)"
}


# Iterate over paired VMs checking their network settings
# -------------------------------------------------------
foreach ($testVM in $testVMs) {
    $benchmarkVM = $vmHashTable[$testVM]

    # Get parameters for new VM
    # -------------------------
    $null = Set-AzContext -SubscriptionId $Subscription
    Add-LogMessage -Level Info "Getting NSG rules and connectivity for $($testVM.Name)"
    $testRules = Get-NSGRules -VM $testVM
    # Check that each NSG rule has a matching equivalent (which might be named differently)
    Add-LogMessage -Level Info "Comparing NSG rules for $($benchmarkVM.Name) and $($testVM.Name)"
    Add-LogMessage -Level Info "... ensuring that all $($benchmarkVM.Name) rules exist on $($testVM.Name)"
    Compare-NSGRules -BenchmarkRules $benchmarkVM.Rules -TestRules $testRules
    Add-LogMessage -Level Info "... ensuring that all $($testVM.Name) rules exist on $($benchmarkVM.Name)"
    Compare-NSGRules -BenchmarkRules $testRules -TestRules $benchmarkVM.Rules

    # Check that internet connectivity is the same for matched VMs
    Add-LogMessage -Level Info "Comparing internet connectivity for $($benchmarkVM.Name) and $($testVM.Name)..."
    # Test internet access on ports 80 and 443
    foreach ($port in (80, 443)) {
        $testInternet = Test-OutboundConnection -VM $testVM -DestinationAddress "google.com" -DestinationPort $port
        if ($benchmarkVM.InternetFromPort[$port] -eq $testInternet) {
            Add-LogMessage -Level Success "The internet is '$($benchmarkVM.InternetFromPort[$port])' on port $port from both"
        } else {
            Add-LogMessage -Level Failure "The internet is '$($benchmarkVM.InternetFromPort[$port])' on port $port from $($benchmarkVM.Name)"
            Add-LogMessage -Level Failure "The internet is '$($testInternet)' on port $port from $($testVM.Name)"
        }
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
