# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(HelpMessage = "Hostname for the VM", mandatory = $false)]
    [string]$ZoneName,
    [Parameter(HelpMessage = "IP Address", mandatory = $false)]
    [string]$ipaddress,
    [Parameter(HelpMessage = "Forced update", mandatory = $false)]
    [String]$update



)
# Check whether the zone exists otherwise create it
if (   (Get-DnsServerZone -name $ZoneName | where-object {$_.ZoneType -eq "Primary"})){
    Write-Output "DNS Zone $ZoneName already exists"
} Else {
    Add-DnsServerPrimaryZone -Name $ZoneName -ReplicationScope "Forest"
    Write-Output "Creating DNS Zone $ZoneName"
}

# Check if the record does not exist and in case create it
if ( -not (Get-DnsServerResourceRecord -ZoneName $ZoneName -RRType "A" -name "@" -ErrorAction silentlycontinue)){

    Add-DnsServerResourceRecordA -Name $ZoneName -ZoneName $ZoneName -IPv4Address $ipaddress
    Write-Output "Creating Record $ZoneName"

# If the record exists and the user used force, first remove it then re-create it
} Else {
    if ($update.ToLower() -eq "force"){
      Remove-DnsServerResourceRecord -ZoneName $ZoneName -RRType "A" -Name "@" -force
      Write-Output "Removing record $ZoneName"

      Add-DnsServerResourceRecordA -Name $ZoneName -ZoneName $ZoneName -IPv4Address $ipaddress
      Write-Output "Creating Record $ZoneName"

    } Else {
      Write-Output "Record $ZoneName already exists, use -dnsForceUpdate 'force' to override"
    }
}

