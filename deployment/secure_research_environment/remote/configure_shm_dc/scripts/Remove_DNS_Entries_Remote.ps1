# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [string]$shmFqdn,
    [string]$sreId,
    [string]$privateDnsZoneName
)

# Remove records for domain-joined SRE VMs
# ----------------------------------------
foreach ($dnsRecord in (Get-DnsServerResourceRecord -ZoneName "$shmFqdn" | Where-Object { $_.HostName -like "*$sreId" })) {
    Write-Output " [ ] Removing '$($dnsRecord.HostName)' DNS record"
    $dnsRecord | Remove-DnsServerResourceRecord -ZoneName "$shmFqdn" -Force
    if ($?) {
        Write-Output " [o] Successfully removed DNS record '$($dnsRecord.HostName)'"
    } else {
        Write-Output " [x] Failed to remove DNS record '$($dnsRecord.HostName)'!"
    }
}

# Remove private endpoint DNS Zone
# --------------------------------
Write-Output " [ ] Removing DNS zone '$privateDnsZoneName'"
Remove-DnsServerZone $privateDnsZoneName -Force
if ($?) {
    Write-Output " [o] Successfully removed DNS zone '$privateDnsZoneName'"
} else {
    Write-Output " [x] Failed to remove DNS zone '$privateDnsZoneName'!"
}
