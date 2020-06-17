# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [String]$sreFqdn
)

# function IpPrefixToInAddrArpa($ipPrefix)
# {
#     $octetList = @($ipPrefix.split("."))
#     [array]::Reverse($octetList)
#     $ipPrefixRev = $octetList -join "."
#     return "$ipPrefixRev.in-addr.arpa"
# }
function Remove-SreDnsZone($zoneName) {
    if(Get-DnsServerZone | Where-Object {$_.ZoneName -eq "$zoneName"}){
        Write-Output " [ ] Removing '$zoneName' DNS record"
        Remove-DnsServerZone $zoneName -Force
        if ($?) {
            Write-Output " [o] Succeeded"
        } else {
            Write-Output " [x] Failed"
            exit 1
        }
    } else {
        Write-Output "No '$zoneName' DNS record exists"
    }
}

Remove-SreDnsZone $sreFqdn
# Remove-SreDnsZone (IpPrefixToInAddrArpa $identitySubnetPrefix)
# Remove-SreDnsZone (IpPrefixToInAddrArpa $rdsSubnetPrefix)
# Remove-SreDnsZone (IpPrefixToInAddrArpa $dataSubnetPrefix)
