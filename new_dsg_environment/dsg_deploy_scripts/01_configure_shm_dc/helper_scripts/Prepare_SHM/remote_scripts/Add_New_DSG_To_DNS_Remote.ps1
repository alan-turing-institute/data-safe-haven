# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $dsgFqdn,
  $dsgDcIp,
  $identitySubnetCidr,
  $rdsSubnetCidr,
  $dataSubnetCidr
)

#Create Reverse Lookup Zones
Write-Output "Adding reverse lookup record for DSG Identity subnet (CIDR: $identitySubnetCidr)"
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId $identitySubnetCidr -ReplicationScope Domain
Write-Output "Adding reverse lookup record for DSG RDS subnet (CIDR: $rdsSubnetCidr)"
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId $rdsSubnetCidr -ReplicationScope Domain
Write-Output "Adding reverse lookup record for DSG Data subnet (CIDR: $dataSubnetCidr)"
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId $dataSubnetCidr -ReplicationScope Domain

#Create conditional forwarders
Write-Output "Adding conditional forwarder record for DSG domain (domain: $dsgFqdn; DSG DC IP: $dsgDcIp)"
Add-DnsServerConditionalForwarderZone -name $dsgFqdn -MasterServers $dsgDcIp -ReplicationScope "Forest"

