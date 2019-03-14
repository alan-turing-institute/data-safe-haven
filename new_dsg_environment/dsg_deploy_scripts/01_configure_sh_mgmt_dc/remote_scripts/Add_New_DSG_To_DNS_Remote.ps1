# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $configJson
)
# For some reason, passing a JSON string as the -Parameter value for Invoke-AzVMRunCommand
# results in the double quotes in the JSON string being stripped in transit
# Escaping these with a single backslash retains the double quotes but the transferred
# string is truncated. Escaping these with backticks still results in the double quotes
# being stripped in transit, but we can then replace the backticks with double quotes 
# at this end to recover a valid JSON string.
$config =  ($configJson.Replace("``","`"") | ConvertFrom-Json)

#Create Reverse Lookup Zones
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId $config.dsg.network.subnets.identity.cidr -ReplicationScope Domain
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId $config.dsg.network.subnets.rds.cidr -ReplicationScope Domain
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId $config.dsg.network.subnets.data.cidr -ReplicationScope Domain

#Create conditional forwarders
Add-DnsServerConditionalForwarderZone -name $config.dsg.domain.fqdn -MasterServers $config.dsg.dc.ip -ReplicationScope "Forest"

