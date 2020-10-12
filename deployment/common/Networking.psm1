Import-Module Az

# Get next available IP address in range
# --------------------------------------
function Get-NextAvailableIpInRange {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of VM to run on")]
        [string]$IpRangeCidr,
        [Parameter(Mandatory = $false, HelpMessage = "Offset to apply before returning an IP address")]
        [int]$Offset,
        [Parameter(Mandatory = $false, HelpMessage = "Virtual network to check availability against")]
        [Microsoft.Azure.Commands.Network.Models.PSVirtualNetwork]$VirtualNetwork
    )
        # Split the input CIDR into the base address and the CIDR mask
        $baseIpAddress, $cidrSuffix = $IpRangeCidr.Split("/")
        $baseIpOctets = $baseIpAddress.Split(".")
        [uint32]$ipNumber = $($baseIpOctets[0] -shl 24) + $($baseIpOctets[1] -shl 16) + $($baseIpOctets[2] -shl 8) + $baseIpOctets[3]

        # Construct the CIDR mask as a series of '1's followed by enough '0's to fill out a 32-bit integer
        [uint32]$cidrMask = 0
        @(1) * $cidrSuffix + @(0) * (32 - $cidrSuffix) | ForEach-Object { $cidrMask = ($cidrMask -shl 1) + $_ }

        # Get the starting and ending IP addresses
        $ipStart = $ipNumber -band $cidrMask
        $ipEnd = $ipNumber -bor (-bnot $cidrMask)

        # Return the full range or filter as required
        $ipAddresses = $ipStart..$ipEnd | ForEach-Object { [System.Net.IPAddress]::parse($_).IPAddressToString }
        if ($VirtualNetwork) {
            $ipAddresses = $ipAddresses | Where-Object { (Test-AzPrivateIPAddressAvailability -VirtualNetwork $VirtualNetwork -IPAddress $_).Available }
        }
        return $ipAddresses | Select-Object -First (1 + $Offset) | Select-Object -Last 1
}
Export-ModuleMember -Function Get-NextAvailableIpInRange


# Get virtual network index for virtual network CIDR range
# --------------------------------------------------------
# A virtual network's index is the zero-indexed position of its 10.x.y.z/21 CIDR range
# within the 10.0.0.0/8 class A private address space.
# There are 8,192 virtual network indexes, ranging from 0 to 8,191
function Get-VirtualNetworkIndex {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Enter virtual network CIDR (must be a 10.x.y.z/21 CIDR)")]
        [string]$CIDR
    )
    $cidrMask = [int](($CIDR).Split("/")[1])
    $firstIpOctet = [int](($CIDR).Split(".")[0])
    $secondIpOctet = [int](($CIDR).Split(".")[1])
    $thirdIpOctet = [int](($CIDR).Split(".")[2])
    if ($firstIpOctet -ne 10 -Or $cidrMask -ne 21) {
        Add-LogMessage -Level Fatal "Invalid virtual network CIDR ($CIDR). Virtual network index is only defined for virtual networks with 10.x.y.z/21 CIDRs"
    }
    else {
        $virtualNetworkIndex = [Math]::Floor(($secondIpOctet * 32) + (($thirdIpOctet) / 8))
        return $virtualNetworkIndex
    }
}
Export-ModuleMember -Function Get-VirtualNetworkIndex
