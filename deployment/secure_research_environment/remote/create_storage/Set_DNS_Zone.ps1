# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Hostname for the VM", Mandatory = $false)]
    [string]$ZoneName,
    [Parameter(HelpMessage = "IP Address", Mandatory = $false)]
    [string]$ipaddress,
    [Parameter(HelpMessage = "Forced update", Mandatory = $false)]
    [String]$update
)

# Check whether the zone exists otherwise create it
if ((Get-DnsServerZone -name $ZoneName -ErrorAction SilentlyContinue | Where-Object { $_.ZoneType -eq "Primary" })) {
    Write-Output "DNS Zone $ZoneName already exists"
} else {
    Write-Output " [ ] Creating DNS Zone ${ZoneName}..."
    Add-DnsServerPrimaryZone -Name $ZoneName -ReplicationScope "Forest"
    if ($?) {
        Write-Output " [o] Successfully created DNS Zone ${ZoneName}"
    } else {
        Write-Output " [x] Failed to create DNS Zone ${ZoneName}!"
    }
}


# If the record exists and the user used force, remove it
if ($update.ToLower() -eq "force") {
    Write-Output " [ ] Removing DNS record ${ZoneName}..."
    Remove-DnsServerResourceRecord -ZoneName $ZoneName -RRType "A" -Name "@" -force -ErrorAction SilentlyContinue
    if ($?) {
        Write-Output " [o] Successfully removed DNS record ${ZoneName}"
    } else {
        Write-Output " [x] Failed to remove DNS record ${ZoneName}!"
    }
}


# Check whether the record exists otherwise create it
if (Get-DnsServerResourceRecord -ZoneName $ZoneName -RRType "A" -name "@" -ErrorAction SilentlyContinue) {
    Write-Output "Record $ZoneName already exists, use -dnsForceUpdate 'force' to override"
} else {
    Write-Output " [ ] Creating DNS record ${ZoneName}..."
    Add-DnsServerResourceRecordA -Name $ZoneName -ZoneName $ZoneName -IPv4Address $ipaddress
    if ($?) {
        Write-Output " [o] Successfully created DNS record ${ZoneName}"
    } else {
        Write-Output " [x] Failed to create DNS record ${ZoneName}!"
    }
}
