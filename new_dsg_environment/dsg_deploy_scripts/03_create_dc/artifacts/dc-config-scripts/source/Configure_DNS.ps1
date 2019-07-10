Param(
  [Parameter(Mandatory = $true, 
             HelpMessage="Enter the CIDR of the Subnet-Identity Network i.e. 10.250.48/24")]
  [ValidateNotNullOrEmpty()]
  [string]$subnetIdentityCidr,
  
  [Parameter(Mandatory = $true, 
             HelpMessage="Enter the CIDR of the Subnet-RDS Network i.e. 10.250.49/24")]
  [ValidateNotNullOrEmpty()]
  [string]$subnetRdsCidr,

  [Parameter(Mandatory = $true, 
             HelpMessage="Enter the CIDR of the Subnet-Data Network i.e. 10.250.50/24")]
  [ValidateNotNullOrEmpty()]
  [string]$subnetDataCidr,

  [Parameter(Mandatory = $true, 
             HelpMessage="Enter FQDN of management domain i.e. turingsafehaven.ac.uk")]
  [ValidateNotNullOrEmpty()]
  [string]$shmFqdn,

  [Parameter(Mandatory = $true, 
             HelpMessage="Enter IP address of management DC")]
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

