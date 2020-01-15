# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $shmFqdn,
  $sreFqdn,
  $sreDcIp,
  $sreDcName,
  $identitySubnetCidr,
  $rdsSubnetCidr,
  $dataSubnetCidr
)

# NB. This function also exists in the SHM configuration (Active_Directory_Configuration.ps1)
# but cannot easily be split out into a common function as it is a remote script and cannot import other scripts
function DNSZoneExists($cidr) {
  $oct1, $oct2, $oct3, $oct4 = $cidr.split(".")
  $zoneName = "$oct3.$oct2.$oct1.in-addr.arpa"
  # Check for a match in existing zone
  $zoneExists = $false
  ForEach ($zone in Get-DnsServerZone) {
    if (($zone.ZoneName -eq $zoneName) -and $zone.IsReverseLookupZone) {
      $zoneExists = $true
    }
  }
  return $zoneExists
}

# Create Reverse Lookup Zones
# ---------------------------
if (DNSZoneExists $identitySubnetCidr) {
  Write-Host " [o] Reverse lookup record for SRE Identity subnet already exists"
} else {
  Write-Host " - Adding reverse lookup record for SRE Identity subnet (CIDR: $identitySubnetCidr)"
  Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId $identitySubnetCidr -ReplicationScope Domain
  if ($?) {
    Write-Host " [o] Successfully created reverse lookup record for SRE Identity subnet"
  } else {
    Write-Host " [x] Failed to create reverse lookup record for SRE Identity subnet"
  }
}

if (DNSZoneExists $rdsSubnetCidr) {
  Write-Host " [o] Reverse lookup record for SRE RDS subnet already exists"
} else {
  Write-Host " - Adding reverse lookup record for SRE RDS subnet (CIDR: $rdsSubnetCidr)"
  Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId $rdsSubnetCidr -ReplicationScope Domain
  if ($?) {
    Write-Host " [o] Successfully created reverse lookup record for SRE RDS subnet"
  } else {
    Write-Host " [x] Failed to create reverse lookup record for SRE RDS subnet"
  }
}

if (DNSZoneExists $dataSubnetCidr) {
  Write-Host " [o] Reverse lookup record for SRE Data subnet already exists"
} else {
  Write-Host " - Adding reverse lookup record for SRE Data subnet (CIDR: $dataSubnetCidr)"
  Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId $dataSubnetCidr -ReplicationScope Domain
  if ($?) {
    Write-Host " [o] Successfully created reverse lookup record for SRE Data subnet"
  } else {
    Write-Host " [x] Failed to create reverse lookup record for SRE Data subnet"
  }
}

# Create conditional forwarder / zone delegation
# ----------------------------------------------
# Check whether the SRE fqdn ends with the SHM fqdn
if ($sreFqdn -match "$($shmFqdn)$") {
  $childzone = $sreFqdn -replace ".$($shmFqdn)$"
  Write-Host " - Adding zone delegation record for SRE subdomain (domain: $sreFqdn; SRE DC IP: $sreDcIp)"
  Add-DnsServerZoneDelegation -Name $shmFqdn -ChildZoneName $childzone -NameServer $sreDcName -IPAddress $sreDcIp
} else {
  Write-Host " - Adding conditional forwarder record for SRE domain (domain: $sreFqdn; SRE DC IP: $sreDcIp)"
  Add-DnsServerConditionalForwarderZone -name $sreFqdn -MasterServers $sreDcIp -ReplicationScope "Forest"
}
if ($?) {
  Write-Host " [o] Successfully created/updated record for SRE domain"
} else {
  Write-Host " [x] Failed to create/update record for SRE domain"
}
