# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "FQDNs for which to create DNS zones", Mandatory = $false)]
    [string]$privateEndpointFqdnsB64,
    [Parameter(HelpMessage = "IP address", Mandatory = $false)]
    [string]$IpAddress
)


# Deserialise Base-64 encoded variables
# -------------------------------------
$privateEndpointFqdns = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($privateEndpointFqdnsB64)) | ConvertFrom-Json


# Deserialise FQDN names and configure the DNS record for each one
# ----------------------------------------------------------------
foreach ($privateEndpointFqdn in $privateEndpointFqdns) {
    # Check whether the zone exists otherwise create it
    if (Get-DnsServerZone -Name $privateEndpointFqdn -ErrorAction SilentlyContinue | Where-Object { $_.ZoneType -eq "Primary" }) {
        Write-Output "DNS zone $privateEndpointFqdn already exists"
    } else {
        Write-Output " [ ] Creating DNS primary zone for $privateEndpointFqdn..."
        Add-DnsServerPrimaryZone -Name $privateEndpointFqdn -ReplicationScope "Forest"
        if ($?) {
            Write-Output " [o] Successfully created DNS primary zone for $privateEndpointFqdn"
        } else {
            Write-Output " [x] Failed to create DNS primary zone for $privateEndpointFqdn!"
        }
    }

    # If the record exists then remove it
    if (Get-DnsServerResourceRecord -ZoneName $privateEndpointFqdn -RRType "A" -name "@" -ErrorAction SilentlyContinue) {
        Write-Output " [ ] Removing existing DNS record $privateEndpointFqdn..."
        Remove-DnsServerResourceRecord -ZoneName $privateEndpointFqdn -RRType "A" -Name "@" -Force -ErrorVariable Failed -ErrorAction SilentlyContinue
        if ($? -and -not $Failed) {
            Write-Output " [o] Successfully removed DNS record $privateEndpointFqdn"
        } else {
            Write-Output " [x] Failed to remove DNS record $privateEndpointFqdn!"
        }
    }

    # Create the record
    Write-Output " [ ] Creating DNS record for $privateEndpointFqdn..."
    Add-DnsServerResourceRecordA -Name $privateEndpointFqdn -ZoneName $privateEndpointFqdn -IPv4Address $IpAddress
    if ($?) {
        Write-Output " [o] Successfully created DNS record for $privateEndpointFqdn"
    } else {
        Write-Output " [x] Failed to create DNS record for $privateEndpointFqdn!"
    }
}
