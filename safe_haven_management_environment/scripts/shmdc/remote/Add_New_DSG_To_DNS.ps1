# Param(
#   [Parameter(Mandatory = $true,
#              HelpMessage="Enter the first 24 bits of the Subnet-Identity Network i.e. 10.250.48")]
#   [ValidateNotNullOrEmpty()]
#   [string]$SubnetIdentity,

#   [Parameter(Mandatory = $true,
#              HelpMessage="Enter the first 24 bits of the Subnet-RDS Network i.e. 10.250.49")]
#   [ValidateNotNullOrEmpty()]
#   [string]$SubnetRDS,

#   [Parameter(Mandatory = $true,
#              HelpMessage="Enter the first 24 bits of the Subnet-Data Network i.e. 10.250.50")]
#   [ValidateNotNullOrEmpty()]
#   [string]$SubnetData,

#   [Parameter(Mandatory = $true,
#              HelpMessage="Enter Domain NetBios Name i.e. DSGROUP2")]
#   [ValidateNotNullOrEmpty()]
#   [string]$Domain,

#   [Parameter(Mandatory = $true,
#              HelpMessage="Enter FQDN of new DSG domain i.e. DSGROUP2.CO.UK")]
#   [ValidateNotNullOrEmpty()]
#   [string]$fqdn,

#   [Parameter(Mandatory = $true,
#              HelpMessage="Enter the IP address of the DC in the new DSG")]
#   [ValidateNotNullOrEmpty()]
#   [string]$dcip
# )

# # Create Reverse Lookup Zones
# Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId "$subnetidentity/24" -ReplicationScope Domain
# Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId "$subnetrds/24" -ReplicationScope Domain
# Add-DnsServerPrimaryZone -DynamicUpdate Secure -NetworkId "$subnetdata/24" -ReplicationScope Domain

# # Create conditional forwarders
# Add-DnsServerConditionalForwarderZone -name $fqdn -MasterServers $dcip -ReplicationScope "Forest"
# Write-Host "DNS Updated"