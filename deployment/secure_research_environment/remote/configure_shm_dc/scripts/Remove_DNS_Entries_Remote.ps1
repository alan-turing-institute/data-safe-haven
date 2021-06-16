# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $false, HelpMessage = "FQDN for the SHM")]
    [string]$ShmFqdn,
    [Parameter(Mandatory = $false, HelpMessage = "FQDN for the SRE")]
    [string]$SreFqdn,
    [Parameter(Mandatory = $false, HelpMessage = "SRE ID")]
    [string]$SreId,
    [Parameter(Mandatory = $false, HelpMessage = "Base-64 encoded list of private DNS zone name-fragments to remove")]
    [string]$PrivateEndpointFragmentsB64
)

# Deserialise Base-64 encoded variables
# -------------------------------------
$PrivateEndpointFragments = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($PrivateEndpointFragmentsB64)) | ConvertFrom-Json


# Remove any records for domain-joined SRE VMs in the SHM zone
# ------------------------------------------------------------
Write-Output "Removing SRE DNS records..."
foreach ($dnsRecord in (Get-DnsServerResourceRecord -ZoneName "$ShmFqdn" | Where-Object { $_.HostName -like "*$SreId" })) {
    $dnsRecord | Remove-DnsServerResourceRecord -ZoneName "$ShmFqdn" -Force
    if ($?) {
        Write-Output " [o] Successfully removed DNS record '$($dnsRecord.HostName)'"
    } else {
        Write-Output " [x] Failed to remove DNS record '$($dnsRecord.HostName)'!"
    }
}


# Remove the forward lookup zone if it exists
# -------------------------------------------
Write-Output "Removing SRE DNS zone..."
if (Get-DnsServerZone -Name $SreFqdn -ErrorAction SilentlyContinue) {
    Write-Output " [ ] Removing DNS zone for '$SreFqdn'..."
    Remove-DnsServerZone -Name $SreFqdn -Force
    if ($?) {
        Write-Output " [o] Successfully removed DNS zone for '$SreFqdn'"
    } else {
        Write-Output " [x] Failed to removed DNS zone for '$SreFqdn'!"
    }
}


# Remove private endpoint DNS Zone
# --------------------------------
foreach ($PrivateEndpointFragment in $PrivateEndpointFragments) {
    Write-Output " [ ] Ensuring that DNS zones matching '$PrivateEndpointFragment' are removed"
    $DnsZones = Get-DnsServerZone | Where-Object { $_.ZoneName -like "${PrivateEndpointFragment}*.core.windows.net" }
    if ($DnsZones) {
        foreach ($DnsZone in $DnsZones) {
            try {
                $DnsZone | Remove-DnsServerZone -Force
                Write-Output " [o] Successfully removed '$($DnsZone.ZoneName)' DNS zone"
            } catch [System.ArgumentException] {
                Write-Output " [x] Failed to remove '$($DnsZone.ZoneName)' DNS zone!"
            }
        }
    } else {
        Write-Output " [o] No DNS zones matching '$PrivateEndpointFragment' were found"
    }
}
