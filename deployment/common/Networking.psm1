Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/Logging -ErrorAction Stop


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
            $ipAddresses = $ipAddresses | Where-Object { (Test-AzPrivateIPAddressAvailability -VirtualNetwork $VirtualNetwork -IPAddress $_).Available }
        }
        if (-not $ipAddresses) {
            Add-LogMessage -Level Fatal "There are no free IP addresses in '$IpRangeCidr' after applying the offset '$Offset'!"
        }
        return $ipAddresses | Select-Object -First 1
}
Export-ModuleMember -Function Get-NextAvailableIpInRange


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
        Add-LogMessage -Level Fatal "Error removing existing rules. Network Security Group '$($NetworkSecurityGroup.Name)' left unchanged." -Exception $_.Exception
    }
    try {
        foreach ($rule in $Rules) {
            $NetworkSecurityGroup = Add-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup @rule
        }
    } catch {
        Add-LogMessage -Level Fatal "Error adding provided rules. Network Security Group '$($NetworkSecurityGroup.Name)' left unchanged." -Exception $_.Exception
    }
    $NetworkSecurityGroup = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $NetworkSecurityGroup
    $updatedRules = @(Get-AzNetworkSecurityRuleConfig -NetworkSecurityGroup $NetworkSecurityGroup)
    foreach ($updatedRule in $updatedRules) {
        $sourceAddressText = ($updatedRule.SourceAddressPrefix -eq "*") ? "any source" : $updatedRule.SourceAddressPrefix
        $destinationAddressText = ($updatedRule.DestinationAddressPrefix -eq "*") ? "any destination" : $updatedRule.DestinationAddressPrefix
        $destinationPortText = ($updatedRule.DestinationPortRange -eq "*") ? "any port" : "ports $($updatedRule.DestinationPortRange)"
        Add-LogMessage -Level Success "Set $($updatedRule.Name) rule to $($updatedRule.Access) connections from $sourceAddressText to $destinationPortText on $destinationAddressText."
    }
    return $NetworkSecurityGroup
}
Export-ModuleMember -Function Set-NetworkSecurityGroupRules
