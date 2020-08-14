# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "SRE ID")]
    $sreId,
    [Parameter(HelpMessage = "SRE Virtual Network Index")]
    $sreVirtualNetworkIndex,
    [Parameter(HelpMessage = "Comma separated list of CIDR ranges to block external DNS resolution for.")]
    $blockedCidrsList,
    [Parameter(HelpMessage = "Comma separated list of CIDR ranges to within the blocked ranges to exceptionally allow external DNS resolution for.")]
    $exceptionalAllowedCidrsList
)
$allowedCidrs = $exceptionalAllowedCidrsList.Split(",")
$blockedCidrs = $blockedCidrsList.Split(",")

$minAllowedProcessingOrder = 3000000000 + ([int]$sreVirtualNetworkIndex * 100)
$minBlockedProcessingOrder = 3500000000 + ([int]$sreVirtualNetworkIndex * 100)

# Create DNS client subnets for CIDRs
# -----------------------------------
function Get-DnsClientSubnetNameFromCidr {
    param(
        $cidr
    )
    return "sre-$sreId-$($cidr.Replace('/','_'))"
}

foreach ($cidr in ($allowedCidrs + $blockedCidrs)) {
    $subnetName = Get-DnsClientSubnetNameFromCidr $cidr
    Write-Output " [ ] Creating '$subnetName' DNS Client Subnet for CIDR '$cidr'"
    $subnet = Get-DnsServerClientSubnet -Name $subnetName -ErrorAction SilentlyContinue
    if ($subnet) {
        Write-Output " [o] '$subnetName' DNS Client Subnet for CIDR '$cidr' already exists."
    } else {
        try {
            $subnet = Add-DnsServerClientSubnet -Name $subnetName -IPv4Subnet $cidr
            Write-Output " [o] Successfully created '$subnetName' DNS Client Subnet for CIDR '$cidr'"
        } catch {
            Write-Output " [x] Failed to create '$subnetName' DNS Client Subnet for CIDR '$cidr'"
            Write-Output $_.Exception
        }
    }
}

