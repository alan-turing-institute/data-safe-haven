# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
  [Parameter(HelpMessage="Enter the CIDR of the Subnet-Identity Network i.e. 10.250.48/24")]
  [ValidateNotNullOrEmpty()]
  [string]$identitySubnetCidr,
  [Parameter(HelpMessage="Enter the CIDR of the Subnet-RDS Network i.e. 10.250.49/24")]
  [ValidateNotNullOrEmpty()]
  [string]$rdsSubnetCidr,
  [Parameter(HelpMessage="Enter the CIDR of the Subnet-Data Network i.e. 10.250.50/24")]
  [ValidateNotNullOrEmpty()]
  [string]$dataSubnetCidr,
  [Parameter(HelpMessage="Enter FQDN of management domain i.e. turingsafehaven.ac.uk")]
  [ValidateNotNullOrEmpty()]
  [string]$shmFqdn,
  [Parameter(HelpMessage="Enter IP address of management DC")]
  [ValidateNotNullOrEmpty()]
  [string]$shmDcIp
)


# Create Reverse Lookup Zones for SRE
Write-Host "Creating reverse lookup zones..."
ForEach($cidr in ($identitySubnetCidr, $rdsSubnetCidr, $dataSubnetCidr)) {
  $oct1, $oct2, $oct3, $oct4 = $cidr.split(".")
  $zoneName = "$oct3.$oct2.$oct1.in-addr.arpa"
  # Check for a match in existing zone
  $zoneExists = $false
  ForEach ($zone in Get-DnsServerZone) {
    if (($zone.ZoneName -eq $zoneName) -and $zone.IsReverseLookupZone) {
      $zoneExists = $true
    }
  }
  # Create reverse lookup zone if it does not already exist
  if ($zoneExists) {
    Write-Host " [o] Reverse lookup zone for $cidr already exists"
  } else {
    Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId "$cidr" -ReplicationScope Domain
    if ($?) {
      Write-Host " [o] Reverse lookup zone for $cidr created successfully"
    } else {
      Write-Host " [x] Reverse lookup zone for $cidr could not be created!"
    }
  }
}


# Create conditional forwarder
# ----------------------------
Write-Host "Adding conditional forwarder zone for SRE domain (domain: $shmFqdn; SRE DC IP: $shmDcIp)..."
$zoneExists = $false
ForEach ($zone in Get-DnsServerZone) {
  if (($zone.ZoneName -eq $shmFqdn) -and $zone.ZoneType -eq "Forwarder") {
    $zoneExists = $true
  }
}
if ($zoneExists) {
    Write-Host " [o] Conditional forwarder zone for SRE domain already exists"
} else {
  Add-DnsServerConditionalForwarderZone -name $shmFqdn -MasterServers $shmDcIp -ReplicationScope "Forest"
  if ($?) {
    Write-Host " [o] Successfully created conditional forwarder zone for SRE domain"
  } else {
    Write-Host " [x] Failed to create conditional forwarder zone for SRE domain"
  }
}

# Create DNS Forwarders
# ---------------------
Write-Host "Adding DNS forwarding..."
Add-DnsServerForwarder -IPAddress 168.63.129.16, 8.8.8.8 -PassThru
if ($?) {
  Write-Host " [o] Successfully created/updated DNS forwarding"
} else {
  Write-Host " [x] Failed to create/update DNS forwarding!"
}

