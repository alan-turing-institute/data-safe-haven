# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
Param(
  [Parameter(HelpMessage="Enter the CIDR of the Subnet-Identity Network i.e. 10.250.48/24")]
  [ValidateNotNullOrEmpty()]
  [string]$subnetIdentityCidr,
  
  [Parameter(HelpMessage="Enter the CIDR of the Subnet-RDS Network i.e. 10.250.49/24")]
  [ValidateNotNullOrEmpty()]
  [string]$subnetRdsCidr,

  [Parameter(HelpMessage="Enter the CIDR of the Subnet-Data Network i.e. 10.250.50/24")]
  [ValidateNotNullOrEmpty()]
  [string]$subnetDataCidr,

  [Parameter(HelpMessage="Enter FQDN of management domain i.e. turingsafehaven.ac.uk")]
  [ValidateNotNullOrEmpty()]
  [string]$shmFqdn,

  [Parameter(HelpMessage="Enter IP address of management DC")]
  [ValidateNotNullOrEmpty()]
  [string]$shmDcIp
)

#Create Reverse Lookup Zones
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId "$subnetIdentityCidr" -ReplicationScope Domain
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId "$subnetRdsCidr" -ReplicationScope Domain
Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId "$subnetDataCidr" -ReplicationScope Domain

#Create conditional forwarders
Add-DnsServerConditionalForwarderZone -name $shmFqdn -MasterServers $shmDcIp -ReplicationScope "Forest"

#Create DNS Forwarders
Add-DnsServerForwarder -IPAddress 168.63.129.16, 8.8.8.8 -PassThru

