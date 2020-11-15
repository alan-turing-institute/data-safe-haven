# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "FQDN for the SRE", Mandatory = $false)]
    [string]$Fqdn,
    [Parameter(HelpMessage = "Host name of the VM", Mandatory = $false)]
    [string]$HostName,
    [Parameter(HelpMessage = "Desired IP Address", Mandatory = $false)]
    [string]$IpAddress
)

# Get the existing record
try {
    $ExistingDnsRecord = Get-DnsServerResourceRecord -ZoneName $Fqdn -Name $HostName -ErrorAction SilentlyContinue
    Write-Output " [o] Successfully retrieved DNS record for '$HostName'"
} catch [Microsoft.Management.Infrastructure.CimException] {
    Write-Output " [x] Failed to retrieve DNS record for '$HostName'!"
}

# Update the record
if ($ExistingDnsRecord.RecordData.IPv4Address.ToString() -eq $IpAddress) {
    Write-Output " [o] DNS record for '$HostName' is already set to '$IpAddress'"
} else {
    try {
        $NewDnsRecord = $ExistingDnsRecord.Clone()
        $NewDnsRecord.RecordData.IPv4Address=[System.Net.IPAddress]::parse($IpAddress)
        $null = Set-DnsServerResourceRecord -NewInputObject $NewDnsRecord -OldInputObject $ExistingDnsRecord -ZoneName $Fqdn -PassThru
        Write-Output " [o] Successfully updated DNS record for '$HostName' to point to '$IpAddress'"
    } catch [Microsoft.Management.Infrastructure.CimException] {
        Write-Output " [x] Failed to update DNS record for '$HostName'!"
    }
}