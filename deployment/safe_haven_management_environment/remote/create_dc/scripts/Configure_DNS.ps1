# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "IP address for the external (Azure) DNS resolver")]
    [ValidateNotNullOrEmpty()]
    [string]$ExternalDnsResolver,
    [Parameter(HelpMessage = "IP addresses for the domain controllers")]
    [ValidateNotNullOrEmpty()]
    [string]$IdentitySubnetCidr
)


# Use Microsoft Azure DNS server for resolving external addresses
# ---------------------------------------------------------------
Write-Output "Forward external DNS requests to Microsoft Azure DNS server..."
Add-DnsServerForwarder -IPAddress "$ExternalDnsResolver" -PassThru
if ($?) {
    Write-Output " [o] Successfully created/updated DNS forwarding"
} else {
    Write-Output " [x] Failed to create/update DNS forwarding!"
}


# Check whether the reverse lookup zone exists, otherwise create it
# -----------------------------------------------------------------
$IpOctets = $IdentitySubnetCidr.Split(".")
$ZoneName = "$($IpOctets[2]).$($IpOctets[1]).$($IpOctets[0]).in-addr.arpa"
if (Get-DnsServerZone -Name $ZoneName -ErrorAction SilentlyContinue | Where-Object { $_.IsReverseLookupZone }) {
    Write-Output "Reverse-lookup zone for '$IdentitySubnetCidr' already exists"
} else {
    Write-Output " [ ] Creating reverse-lookup zone for '$IdentitySubnetCidr'..."
    Add-DnsServerPrimaryZone -NetworkID $IdentitySubnetCidr -ReplicationScope "Forest"
    if ($?) {
        Write-Output " [o] Successfully created reverse-lookup zone for '$IdentitySubnetCidr'"
    } else {
        Write-Output " [x] Failed to create reverse-lookup zone for '$IdentitySubnetCidr'!"
    }
}
