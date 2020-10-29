# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "FQDN for the SHM", Mandatory = $false)]
    [string]$shmFqdn,
    [Parameter(HelpMessage = "SRE ID", Mandatory = $false)]
    [string]$sreId,
    [Parameter(HelpMessage = "Name of the private DNS zone", Mandatory = $false)]
    [string]$privateDnsZoneName
)

# Remove records for domain-joined SRE VMs
# ----------------------------------------
Write-Output "Removing SRE DNS records..."
foreach ($dnsRecord in (Get-DnsServerResourceRecord -ZoneName "$shmFqdn" | Where-Object { $_.HostName -like "*$sreId" })) {
    $dnsRecord | Remove-DnsServerResourceRecord -ZoneName "$shmFqdn" -Force
    if ($?) {
        Write-Output " [o] Successfully removed DNS record '$($dnsRecord.HostName)'"
    } else {
        Write-Output " [x] Failed to remove DNS record '$($dnsRecord.HostName)'!"
    }
}

# Remove private endpoint DNS Zone
# --------------------------------
if ($privateDnsZoneName) {
    Write-Output " [ ] Ensuring that '$privateDnsZoneName' DNS zone is removed"
    if (Get-DnsServerZone -Name $privateDnsZoneName -ErrorAction SilentlyContinue) {
        try {
            Remove-DnsServerZone $privateDnsZoneName -force
            Write-Output " [o] Successfully removed '$privateDnsZoneName' DNS zone"
        } catch [System.ArgumentException] {
            Write-Output " [x] Failed to remove '$privateDnsZoneName' DNS zone!"
        }
    } else {
        Write-Output " [o] '$privateDnsZoneName' DNS zone does not exist"
    }
}
