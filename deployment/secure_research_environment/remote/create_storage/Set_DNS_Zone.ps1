# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Name of the DNS zone", Mandatory = $false)]
    [string]$Name,
    [Parameter(HelpMessage = "IP Address", Mandatory = $false)]
    [string]$IpAddress
)

# Check whether the zone exists otherwise create it
if (Get-DnsServerZone -name $Name -ErrorAction SilentlyContinue | Where-Object { $_.ZoneType -eq "Primary" }) {
    Write-Output "DNS zone $Name already exists"
} else {
    Write-Output " [ ] Creating DNS zone $Name..."
    Add-DnsServerPrimaryZone -Name $Name -ReplicationScope "Forest"
    if ($?) {
        Write-Output " [o] Successfully created DNS zone $Name"
    } else {
        Write-Output " [x] Failed to create DNS zone $Name!"
    }
}

# If the record exists then remove it
if (Get-DnsServerResourceRecord -ZoneName $Name -RRType "A" -name "@" -ErrorAction SilentlyContinue) {
    Write-Output " [ ] Removing existing DNS record $Name..."
    Remove-DnsServerResourceRecord -ZoneName $Name -RRType "A" -Name "@" -Force -ErrorVariable failed -ErrorAction SilentlyContinue
    if ($? -and -not $failed) {
        Write-Output " [o] Successfully removed DNS record $Name"
    } else {
        Write-Output " [x] Failed to remove DNS record $Name!"
    }
}

# Create the record
Write-Output " [ ] Creating DNS record $Name..."
Add-DnsServerResourceRecordA -Name $Name -ZoneName $Name -IPv4Address $IpAddress
if ($?) {
    Write-Output " [o] Successfully created DNS record $Name"
} else {
    Write-Output " [x] Failed to create DNS record $Name!"
}
