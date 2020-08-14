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

# Create DNS client subnets for allowed CIDRs
foreach ($allowedCidr in $allowedCidrs) {
    $subnetName = "sre-$sreId-allow-$($allowedCidr.Replace('/','_'))"
    Write-Output " [ ] Creating '$subnetName' DNS Client Subnet for CIDR '$allowedCidr'"
    $subnet = Get-DnsServerClientSubnet -Name $subnetName -ErrorAction SilentlyContinue
    if ($subnet) {
        Write-Output " [o] '$subnetName' DNS Client Subnet for CIDR '$allowedCidr' already exists."
    } else {
        try {
            $null = Add-DnsServerClientSubnet -Name $subnetName -IPv4Subnet $allowedCidr
            Write-Output " [o] Successfully created '$subnetName' DNS Client Subnet for CIDR '$allowedCidr'"
        } catch {
            Write-Output " [x] Failed to create '$subnetName' DNS Client Subnet for CIDR '$allowedCidr'"
            Write-Output $_.Exception
        }
    }
}

# Create DNS client subnets for blocked CIDRs
foreach ($blockedCidr in $blockedCidrs) {
    $subnetName = "sre-$sreId-blocked-$($allowedCidr.Replace('/','_'))"
    Write-Output " [ ] Creating '$subnetName' DNS Client Subnet for CIDR '$blockedCidr'"
    $subnet = Get-DnsServerClientSubnet -Name $subnetName -ErrorAction SilentlyContinue
    if ($subnet) {
        Write-Output " [o] '$subnetName' DNS Client Subnet for CIDR '$blockedCidr' already exists."
    } else {
        try {
            $null = Add-DnsServerClientSubnet -Name $subnetName -IPv4Subnet $blockedCidr
            Write-Output " [o] Successfully created '$subnetName' DNS Client Subnet for CIDR '$blockedCidr'"
        } catch {
            Write-Output " [x] Failed to create '$subnetName' DNS Client Subnet for CIDR '$blockedCidr'"
            Write-Output $_.Exception
        }
    }
}