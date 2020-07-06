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
