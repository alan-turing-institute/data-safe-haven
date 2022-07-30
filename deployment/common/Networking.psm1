Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module $PSScriptRoot/AzureResources -ErrorAction Stop
Import-Module $PSScriptRoot/Deployments -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


# Create network security group rule if it does not exist
# -------------------------------------------------------
function Add-NetworkSecurityGroupRule {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of network security group rule to deploy")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "A NetworkSecurityGroup object to apply this rule to")]
        $NetworkSecurityGroup,
        [Parameter(Mandatory = $true, HelpMessage = "A description of the network security rule")]
        [string]$Description,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies the priority of a rule configuration")]
        $Priority,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies whether a rule is evaluated on incoming or outgoing traffic")]
        [string]$Direction,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies whether network traffic is allowed or denied")]
        [string]$Access,
        [Parameter(Mandatory = $true, HelpMessage = "Specifies the network protocol that a rule configuration applies to")]
        [string]$Protocol,
        [Parameter(Mandatory = $true, HelpMessage = "Source addresses. One or more of: a CIDR, an IP address range, a wildcard or an Azure tag (eg. VirtualNetwork)")]
        $SourceAddressPrefix,
        [Parameter(Mandatory = $true, HelpMessage = "Source port or range. One or more of: an integer, a range of integers or a wildcard")]
        $SourcePortRange,
        [Parameter(Mandatory = $true, HelpMessage = "Destination addresses. One or more of: a CIDR, an IP address range, a wildcard or an Azure tag (eg. VirtualNetwork)")]
        $DestinationAddressPrefix,
        [Parameter(Mandatory = $true, HelpMessage = "Destination port or range. One or more of: an integer, a range of integers or a wildcard")]
        $DestinationPortRange,
        [Parameter(Mandatory = $false, HelpMessage = "Print verbose logging messages")]
        [switch]$VerboseLogging = $false
    )
    try {
        if ($VerboseLogging) { Add-LogMessage -Level Info "Ensuring that NSG rule '$Name' exists on '$($NetworkSecurityGroup.Name)'..." }
        $null = Get-AzNetworkSecurityRuleConfig -Name $Name -NetworkSecurityGroup $NetworkSecurityGroup -ErrorVariable notExists -ErrorAction SilentlyContinue
        if ($notExists) {
            if ($VerboseLogging) { Add-LogMessage -Level Info "[ ] Creating NSG rule '$Name'" }
            try {
                $null = Add-AzNetworkSecurityRuleConfig -Name "$Name" `
                                                        -Access "$Access" `
                                                        -Description "$Description" `
                                                        -DestinationAddressPrefix $DestinationAddressPrefix `
                                                        -DestinationPortRange $DestinationPortRange `
                                                        -Direction "$Direction" `
                                                        -NetworkSecurityGroup $NetworkSecurityGroup `
                                                        -Priority $Priority `
                                                        -Protocol "$Protocol" `
                                                        -SourceAddressPrefix $SourceAddressPrefix `
                                                        -SourcePortRange $SourcePortRange `
                                                        -ErrorAction Stop | Set-AzNetworkSecurityGroup -ErrorAction Stop
                if ($VerboseLogging) { Add-LogMessage -Level Success "Created NSG rule '$Name'" }
            } catch {
                Add-LogMessage -Level Fatal "Failed to create NSG rule '$Name'!" -Exception $_.Exception
            }
        } else {
            if ($VerboseLogging) { Add-LogMessage -Level InfoSuccess "Updating NSG rule '$Name'" }
            $null = Set-AzNetworkSecurityRuleConfig -Name "$Name" `
                                                    -Access "$Access" `
                                                    -Description "$Description" `
                                                    -DestinationAddressPrefix $DestinationAddressPrefix `
                                                    -DestinationPortRange $DestinationPortRange `
                                                    -Direction "$Direction" `
                                                    -NetworkSecurityGroup $NetworkSecurityGroup `
                                                    -Priority $Priority `
                                                    -Protocol "$Protocol" `
                                                    -SourceAddressPrefix $SourceAddressPrefix `
                                                    -SourcePortRange $SourcePortRange `
                                                    -ErrorAction Stop | Set-AzNetworkSecurityGroup -ErrorAction Stop
        }
    } catch [Microsoft.Azure.Commands.Network.Common.NetworkCloudException] {
        Add-LogMessage -Level Fatal "Azure network connection failed!" -Exception $_.Exception
    }
}
Export-ModuleMember -Function Add-NetworkSecurityGroupRule


# Add a VM to a domain
# --------------------
function Add-WindowsVMtoDomain {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to domain join")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group for VM to domain join")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Domain name to join")]
        [string]$DomainName,
        [Parameter(Mandatory = $true, HelpMessage = "Username for domain joining account")]
        [string]$DomainJoinUsername,
        [Parameter(Mandatory = $true, HelpMessage = "Password for domain joining account")]
        [System.Security.SecureString]$DomainJoinPassword,
        [Parameter(Mandatory = $true, HelpMessage = "The full distinguished name for the OU to add this VM to")]
        [string]$OUPath,
        [Parameter(Mandatory = $false, HelpMessage = "Force restart of VM if already running")]
        [switch]$ForceRestart
    )
    Add-LogMessage -Level Info "[ ] Attempting to join VM '$Name' to domain '$DomainName'"
    $domainJoinCredentials = New-Object System.Management.Automation.PSCredential("${DomainName}\${DomainJoinUsername}", $DomainJoinPassword)
    $null = Set-AzVMADDomainExtension -VMName $Name -ResourceGroupName $ResourceGroupName -DomainName $DomainName -Credential $domainJoinCredentials -Name "joindomain" -JoinOption 3 -TypeHandlerVersion 1.3 -OUPath $OUPath -Restart:$ForceRestart
    if ($?) {
        Add-LogMessage -Level Success "Joined VM '$Name' to domain '$DomainName'"
    } else {
        Add-LogMessage -Level Fatal "Failed to join VM '$Name' to domain '$DomainName'!"
    }
}
Export-ModuleMember -Function Add-WindowsVMtoDomain


# Convert an IP address into a decimal integer
# --------------------------------------------
function Convert-CidrToIpAddressRange {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input range in CIDR notation")]
        [string]$IpRangeCidr,
        [Parameter(Mandatory = $false, HelpMessage = "Return results as decimal values instead of IP address strings")]
        [switch]$AsDecimal = $false
    )
    # Split the CIDR range into the IP address prefix and the CIDR suffix
    $ipAddressPrefx, $cidrSuffix = $IpRangeCidr.Split("/")

    # Convert the IP prefix and CIDR suffix to decimal
    [uint32]$ipPrefixDecimal = Convert-IpAddressToDecimal -IpAddress $ipAddressPrefx
    [uint32]$cidrMaskDecimal = Convert-CidrSuffixToDecimalMask -Cidr $cidrSuffix

    # Get the starting and ending IP addresses
    $ipStartDecimal = $ipPrefixDecimal -band $cidrMaskDecimal
    $ipEndDecimal = $ipPrefixDecimal -bor (-bnot $cidrMaskDecimal)

    # Return as decimals or IP addresses
    if ($AsDecimal) {
        return @($ipStartDecimal, $ipEndDecimal)
    }
    return @(
        (Convert-DecimalToIpAddress -IpDecimal $ipStartDecimal),
        (Convert-DecimalToIpAddress -IpDecimal $ipEndDecimal)
    )
}
Export-ModuleMember -Function Convert-CidrToIpAddressRange


# Convert an IP address into a decimal integer
# --------------------------------------------
function Convert-CidrSuffixToDecimalMask {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input CIDR")]
        [uint32]$CidrSuffix
    )
    # Construct the CIDR mask as a series of '1's followed by enough '0's to pad the length to 32
    # Now these numbers can be used one-by-one to construct a 32-bit integer
    [uint32]$decimalMask = 0
    @(1) * $CidrSuffix + @(0) * (32 - $CidrSuffix) | ForEach-Object { $decimalMask = ($decimalMask -shl 1) + $_ }
    return $decimalMask
}
Export-ModuleMember -Function Convert-CidrToDecimalMask


# Convert a decimal integer into an IP address
# --------------------------------------------
function Convert-DecimalToIpAddress {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input decimal value")]
        [string]$IpDecimal
    )
    return [System.Net.IPAddress]::parse($IpDecimal).IPAddressToString
}
Export-ModuleMember -Function Convert-DecimalToIpAddress


# Convert an IP address into a decimal integer
# --------------------------------------------
function Convert-IpAddressToDecimal {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input IP address")]
        [string]$IpAddress
    )
    $IpOctets = Convert-IpAddressToOctets -IpAddress $IpAddress
    return [uint32]($($IpOctets[0] -shl 24) + $($IpOctets[1] -shl 16) + $($IpOctets[2] -shl 8) + $IpOctets[3])
}
Export-ModuleMember -Function Convert-IpAddressToDecimal


# Convert an IP address into a set of octets
# ------------------------------------------
function Convert-IpAddressToOctets {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input IP address")]
        [string]$IpAddress
    )
    $nSeparators = ($IpAddress.ToCharArray() | Where-Object { $_ -eq "." } | Measure-Object).Count
    if ($nSeparators -ne 3) {
        Add-LogMessage -Level Fatal "Expected three dot-separators but '$IpAddress' has $nSeparators!"
    }
    return @($IpAddress.Split(".") | ForEach-Object { [uint32]$_ })
}
Export-ModuleMember -Function Convert-IpAddressToOctets


# Convert a set of IP octets into an IP address
# ---------------------------------------------
function Convert-OctetsToIpAddress {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input IP octets")]
        [uint32[]]$IpOctets
    )
    if ($IpOctets.Count -ne 4) {
        Add-LogMessage -Level Fatal "Expected four octets but '$IpOctets' has $($IpOctets.Count)!"
    }
    return $IpOctets -Join "."
}
Export-ModuleMember -Function Convert-OctetsToIpAddress


# Create a private endpoint for an automation account
# ---------------------------------------------------
function Deploy-AutomationAccountEndpoint {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Automation account to create the private endpoint for")]
        [Microsoft.Azure.Commands.Automation.Model.AutomationAccount]$Account,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to deploy into")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet
    )
    $endpoint = Deploy-PrivateEndpoint -Name "$($Account.AutomationAccountName)-endpoint".ToLower() `
                                       -GroupId "DSCAndHybridWorker" `
                                       -Location $Account.Location `
                                       -PrivateLinkServiceId (Get-ResourceId $Account.AutomationAccountName) `
                                       -ResourceGroupName $Account.ResourceGroupName `
                                       -Subnet $Subnet
    return $endpoint

}
Export-ModuleMember -Function Deploy-AutomationAccountEndpoint


# Create a private endpoint for an automation account
# ---------------------------------------------------
function Deploy-MonitorPrivateLinkScopeEndpoint {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Location to deploy the endpoint")]
        [string]$Location,
        [Parameter(Mandatory = $true, HelpMessage = "Private link scope to connect")]
        [Microsoft.Azure.Commands.Insights.OutputClasses.PSMonitorPrivateLinkScope]$PrivateLinkScope,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to deploy into")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet
    )
    # $endpoint = Deploy-PrivateEndpoint -Name "test" `
    $endpoint = Deploy-PrivateEndpoint -Name "$($PrivateLinkScope.Name)-endpoint".ToLower() `
                                       -GroupId "azuremonitor" `
                                       -Location $Location `
                                       -PrivateLinkServiceId $PrivateLinkScope.Id `
                                       -ResourceGroupName (Get-ResourceGroupName $PrivateLinkScope.Name) `
                                       -Subnet $Subnet
    return $endpoint

}
Export-ModuleMember -Function Deploy-MonitorPrivateLinkScopeEndpoint


# Create a private endpoint
# -------------------------
function Deploy-PrivateEndpoint {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Group ID for this endpoint")]
        [string]$GroupId,
        [Parameter(Mandatory = $true, HelpMessage = "Location to deploy the endpoint")]
        [string]$Location,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the endpoint")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "ID of the service to link against")]
        [string]$PrivateLinkServiceId,
        [Parameter(Mandatory = $true, HelpMessage = "Name of resource group to deploy into")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to deploy into")]
        [Microsoft.Azure.Commands.Network.Models.PSSubnet]$Subnet
    )
    Add-LogMessage -Level Info "Ensuring that private endpoint '$Name' exists..."
    $endpoint = Get-AzPrivateEndpoint -Name $Name -ResourceGroupName $ResourceGroupName -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Info "[ ] Creating private endpoint '$Name'"
        $privateLinkServiceConnection = New-AzPrivateLinkServiceConnection -Name "${Name}LinkServiceConnection" -PrivateLinkServiceId $PrivateLinkServiceId -GroupId $GroupId
        $endpoint = New-AzPrivateEndpoint -Name $Name -ResourceGroupName $ResourceGroupName -Location $Location -Subnet $Subnet -PrivateLinkServiceConnection $privateLinkServiceConnection
        if ($?) {
            Add-LogMessage -Level Success "Created private endpoint '$Name'"
        } else {
            Add-LogMessage -Level Fatal "Failed to create private endpoint '$Name'!"
        }
    } else {
        Add-LogMessage -Level InfoSuccess "Private endpoint '$Name' already exists"
    }
    return $endpoint
}
Export-ModuleMember -Function Deploy-PrivateEndpoint


# Get next available IP address in range
# --------------------------------------
function Get-NextAvailableIpInRange {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Input range in CIDR notation")]
        [string]$IpRangeCidr,
        [Parameter(Mandatory = $false, HelpMessage = "Offset to apply before returning an IP address")]
        [int]$Offset,
        [Parameter(Mandatory = $false, HelpMessage = "Virtual network to check availability against")]
        [Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]$VirtualNetwork
    )
    # Get the start and end IP decimals for this CIDR range
    $ipStart, $ipEnd = Convert-CidrToIpAddressRange -IpRangeCidr $IpRangeCidr -AsDecimal

    # Return the full range or filter as required
    $ipAddresses = $ipStart..$ipEnd | ForEach-Object { Convert-DecimalToIpAddress -IpDecimal $_ } | Select-Object -Skip $Offset
    if ($VirtualNetwork) {
        $ipAddress = $ipAddresses | Where-Object { (Test-AzPrivateIPAddressAvailability -VirtualNetwork $VirtualNetwork -IPAddress $_).Available } | Select-Object -First 1
    } else {
        $ipAddress = $ipAddresses | Select-Object -First 1
    }
    if (-not $ipAddress) {
        Add-LogMessage -Level Fatal "There are no free IP addresses in '$IpRangeCidr' after applying the offset '$Offset'!"
    }
    return $ipAddress
}
Export-ModuleMember -Function Get-NextAvailableIpInRange


# Get the virtual network that a given subnet belongs to
# ------------------------------------------------------
function Get-VirtualNetwork {
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Name of virtual network to retrieve")]
        [string]$Name,
        [Parameter(Mandatory = $false, HelpMessage = "Name of resource group that this virtual network belongs to")]
        [string]$ResourceGroupName
    )
    $params = @{}
    if ($Name) { $params["Name"] = $Name }
    if ($ResourceGroupName) { $params["ResourceGroupName"] = $ResourceGroupName }
    return Get-AzVirtualNetwork @params
}
Export-ModuleMember -Function Get-VirtualNetwork


# Set Network Security Group Rules
# --------------------------------
function Set-NetworkSecurityGroupRules {
    param(
        [parameter(Mandatory = $true, HelpMessage = "Network Security Group to set rules for")]
        [Microsoft.Azure.Commands.Network.Models.PSNetworkSecurityGroup]$NetworkSecurityGroup,
        [parameter(Mandatory = $true, HelpMessage = "Rules to set for Network Security Group")]
        [Object[]]$Rules
    )
    Add-LogMessage -Level Info "[ ] Setting $($Rules.Count) rules for Network Security Group '$($NetworkSecurityGroup.Name)'"
    try {
        $existingRules = @(Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup)
        foreach ($existingRule in $existingRules) {
            $NetworkSecurityGroup = Remove-AzNetworkSecurityRuleConfig -Name $existingRule.Name -NetworkSecurityGroup $NetworkSecurityGroup
        }
    } catch {
        Add-LogMessage -Level Fatal "Error removing existing rules from Network Security Group '$($NetworkSecurityGroup.Name)'." -Exception $_.Exception
    }
    try {
        foreach ($rule in $Rules) {
            $null = Add-NetworkSecurityGroupRule -NetworkSecurityGroup $NetworkSecurityGroup @rule
        }
    } catch {
        Add-LogMessage -Level Fatal "Error adding provided rules to Network Security Group '$($NetworkSecurityGroup.Name)'." -Exception $_.Exception
    }
    try {
        $NetworkSecurityGroup = Get-AzNetworkSecurityGroup -Name $NetworkSecurityGroup.Name -ResourceGroupName $NetworkSecurityGroup.ResourceGroupName -ErrorAction Stop
        $updatedRules = @(Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup)
        foreach ($updatedRule in $updatedRules) {
            $sourceAddressText = ($updatedRule.SourceAddressPrefix -eq "*") ? "any source" : $updatedRule.SourceAddressPrefix
            $destinationAddressText = ($updatedRule.DestinationAddressPrefix -eq "*") ? "any destination" : $updatedRule.DestinationAddressPrefix
            $destinationPortText = ($updatedRule.DestinationPortRange -eq "*") ? "any port" : "ports $($updatedRule.DestinationPortRange)"
            Add-LogMessage -Level Success "Set $($updatedRule.Name) rule to $($updatedRule.Access) connections from $sourceAddressText to $destinationPortText on $destinationAddressText."
        }
    } catch {
        Add-LogMessage -Level Fatal "Failed to add one or more NSG rules!" -Exception $_.Exception
    }
    return $NetworkSecurityGroup
}
Export-ModuleMember -Function Set-NetworkSecurityGroupRules


# Update DNS record on the SHM for a VM
# -------------------------------------
function Update-VMDnsRecords {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of primary DC VM")]
        [string]$DcName,
        [Parameter(Mandatory = $true, HelpMessage = "Resource group of primary DC VM")]
        [string]$DcResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "FQDN for this SHM")]
        [string]$BaseFqdn,
        [Parameter(Mandatory = $true, HelpMessage = "Name of the SHM subscription")]
        [string]$ShmSubscriptionName,
        [Parameter(Mandatory = $true, HelpMessage = "Hostname of VM whose records need to be updated")]
        [string]$VmHostname,
        [Parameter(Mandatory = $true, HelpMessage = "IP address for this VM")]
        [string]$VmIpAddress
    )
    # Get original subscription
    $originalContext = Get-AzContext
    try {
        $null = Set-AzContext -SubscriptionId $ShmSubscriptionName -ErrorAction Stop
        Add-LogMessage -Level Info "[ ] Resetting DNS record for VM '$VmHostname'..."
        $params = @{
            Fqdn      = $BaseFqdn
            HostName  = ($VmHostname | Limit-StringLength -MaximumLength 15)
            IpAddress = $VMIpAddress
        }
        $scriptPath = Join-Path $PSScriptRoot "remote" "ResetDNSRecord.ps1"
        $null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $DcName -ResourceGroupName $DcResourceGroupName -Parameter $params
        if ($?) {
            Add-LogMessage -Level Success "Resetting DNS record for VM '$VmHostname' was successful"
        } else {
            Add-LogMessage -Level Failure "Resetting DNS record for VM '$VmHostname' failed!"
        }
    } finally {
        # Switch back to original subscription
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    }
}
Export-ModuleMember -Function Update-VMDnsRecords


# Update subnet and IP address for a VM
# -------------------------------------
function Update-VMIpAddress {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Azure VM object", ParameterSetName = "ByObject")]
        [Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine]$VM,
        [Parameter(Mandatory = $true, HelpMessage = "VM name", ParameterSetName = "ByName")]
        [string]$Name,
        [Parameter(Mandatory = $true, HelpMessage = "VM resource group", ParameterSetName = "ByName")]
        [string]$ResourceGroupName,
        [Parameter(Mandatory = $true, HelpMessage = "Subnet to join")]
        [Microsoft.Azure.Commands.Network.Models.PSChildResource]$Subnet,
        [Parameter(Mandatory = $true, HelpMessage = "IP address to switch to")]
        [string]$IpAddress
    )
    # Get VM if not provided
    if (-not $VM) {
        $VM = Get-AzVM -Name $Name -ResourceGroup $ResourceGroupName
    }
    $networkCard = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $VM.Id }
    if ($networkCard.Count -ne 1) { Add-LogMessage -Level Fatal "Found $($networkCard.Count) network cards for $VMName!" }
    if ($networkCard.IpConfigurations[0].PrivateIpAddress -eq $IpAddress) {
        Add-LogMessage -Level InfoSuccess "IP address for '$($VM.Name)' is already set to '$IpAddress'"
    } else {
        Add-LogMessage -Level Info "Updating subnet and IP address for '$($VM.Name)'..."
        Stop-VM -VM $VM
        $networkCard.IpConfigurations[0].Subnet.Id = $Subnet.Id
        $networkCard.IpConfigurations[0].PrivateIpAddress = $IpAddress
        $null = $networkCard | Set-AzNetworkInterface
        # Validate changes
        $networkCard = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq $VM.Id }
        if ($networkCard.IpConfigurations[0].Subnet.Id -eq $Subnet.Id) {
            Add-LogMessage -Level Info "Set '$($VM.Name)' subnet to '$($Subnet.Name)'"
        } else {
            Add-LogMessage -Level Fatal "Failed to change subnet to '$($Subnet.Name)'!"
        }
        if ($networkCard.IpConfigurations[0].PrivateIpAddress -eq $IpAddress) {
            Add-LogMessage -Level Info "Set '$($VM.Name)' IP address to '$IpAddress'"
        } else {
            Add-LogMessage -Level Fatal "Failed to change IP address to '$IpAddress'!"
        }
        Start-VM -VM $VM
    }
}
Export-ModuleMember -Function Update-VMIpAddress
