# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "FQDNs for which to create DNS zones", Mandatory = $false)]
    [string]$PipeSeparatedFqdns,
    [Parameter(HelpMessage = "IP address", Mandatory = $false)]
    [string]$IpAddress
)


# Deserialise FQDN names and configure the DNS record for each one
foreach ($Fqdn in $PipeSeparatedFqdns.Split("|")) {
    # Check whether the zone exists otherwise create it
    if (Get-DnsServerZone -Name $Fqdn -ErrorAction SilentlyContinue | Where-Object { $_.ZoneType -eq "Primary" }) {
        Write-Output "DNS zone $Fqdn already exists"
    } else {
        Write-Output " [ ] Creating DNS primary zone for $Fqdn..."
        Add-DnsServerPrimaryZone -Name $Fqdn -ReplicationScope "Forest"
        if ($?) {
            Write-Output " [o] Successfully created DNS primary zone for $Fqdn"
        } else {
            Write-Output " [x] Failed to create DNS primary zone for $Fqdn!"
        }
    }

    # If the record exists then remove it
    if (Get-DnsServerResourceRecord -ZoneName $Fqdn -RRType "A" -name "@" -ErrorAction SilentlyContinue) {
        Write-Output " [ ] Removing existing DNS record $Fqdn..."
        Remove-DnsServerResourceRecord -ZoneName $Fqdn -RRType "A" -Name "@" -Force -ErrorVariable Failed -ErrorAction SilentlyContinue
        if ($? -and -not $Failed) {
            Write-Output " [o] Successfully removed DNS record $Fqdn"
        } else {
            Write-Output " [x] Failed to remove DNS record $Fqdn!"
        }
    }

    # Create the record
    Write-Output " [ ] Creating DNS record for $Fqdn..."
    Add-DnsServerResourceRecordA -Name $Fqdn -ZoneName $Fqdn -IPv4Address $IpAddress
    if ($?) {
        Write-Output " [o] Successfully created DNS record for $Fqdn"
    } else {
        Write-Output " [x] Failed to create DNS record for $Fqdn!"
    }
}