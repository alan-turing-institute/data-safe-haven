# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $false, HelpMessage = "FQDN for the SRE")]
    [string]$SreFqdn
)

# Check whether the forward lookup zone exists, otherwise create it
# -----------------------------------------------------------------
if (Get-DnsServerZone -Name $SreFqdn -ErrorAction SilentlyContinue) {
    Write-Output "DNS zone for $SreFqdn already exists"
} else {
    Write-Output " [ ] Creating DNS zone for '$SreFqdn'..."
    Add-DnsServerPrimaryZone -Name $SreFqdn -ReplicationScope "Forest" -PassThru
    if ($?) {
        Write-Output " [o] Successfully created DNS zone for '$SreFqdn'"
    } else {
        Write-Output " [x] Failed to create DNS zone for '$SreFqdn'!"
    }
}
