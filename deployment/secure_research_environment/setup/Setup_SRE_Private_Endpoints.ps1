# Setup script that creates private endpoints to Azure resources that already
# exist and are listed in the 'privateEndpoints' element of the SRE configuration.
#
# Based on the Azure Quickstart guide at:
# https://docs.microsoft.com/en-us/azure/private-link/create-private-endpoint-powershell

param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId
)

Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force

# Get the SRE config
# ------------------
$config = Get-SreConfig $sreId

# Loop over the private endpoints in the configuration
# ----------------------------------------------------
Foreach ($pe in $config.sre.privateEndpoints) {

  # Temp test:
  # Write-Output $pe.subscriptionName

  # Switch to the subscription containing the target resource
  # ---------------------------------------------------------
  $_ = Set-AzContext -Subscription $pe.subscriptionName
  $resource = Get-AzResource -Name $pe.resourceName -ExpandProperties

  # Switch to the SRE subscription
  # ------------------------------
  $_ = Set-AzContext -Subscription $config.sre.subscriptionName

  # Create the private endpoint
  # ---------------------------
  Add-LogMessage -Level Info "Creating private endpoint '$($pe.privateEndpointName)' to resource '$($resource.Name)'"

  $privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$($pe.privateEndpointName)ServiceConnection" `
    -PrivateLinkServiceId $resource.ResourceId `
    -GroupId $pe.PrivateLinkServiceConnectionGroupId

  $virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name

  $subnet = $virtualNetwork `
    | Select -ExpandProperty subnets `
    | Where-Object  {$_.Name -eq $config.sre.network.subnets.data.name}

  $privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $config.sre.network.vnet.rg `
    -Name $pe.privateEndpointName `
    -Location $config.sre.Location `
    -Subnet $subnet `
    -PrivateLinkServiceConnection $privateEndpointConnection

  # Create a Private DNS Zone
  # ----------------------------
  $privateDnsZoneName = $resource.Properties.fullyQualifiedDomainName -replace $resource.Name, "privatelink" -replace "azure.com", "windows.net"
  Add-LogMessage -Level Info "Creating private DNS zone '$($privateDnsZoneName)'"
  $zone = New-AzPrivateDnsZone -ResourceGroupName $config.sre.network.vnet.rg `
    -Name $privateDnsZoneName

  $privateDnsVirtualNetworkLinkName = "$($resource.Name)VirtualNetworkLink"
  Add-LogMessage -Level Info "Creating private DNS virtual network link '$($privateDnsVirtualNetworkLinkName)'"
  $link  = New-AzPrivateDnsVirtualNetworkLink -ResourceGroupName $config.sre.network.vnet.rg `
    -ZoneName $privateDnsZoneName `
    -Name $privateDnsVirtualNetworkLinkName `
    -VirtualNetworkId $virtualNetwork.Id

  # The hard-coded API version "2019-04-01" specified here is necessary for
  # obtaining the required IP config properties below.
  $networkInterface = Get-AzResource `
    -ResourceId $privateEndpoint.NetworkInterfaces[0].Id `
    -ApiVersion "2019-04-01"

  foreach ($ipconfig in $networkInterface.properties.ipConfigurations) {
    foreach ($fqdn in $ipconfig.properties.privateLinkConnectionProperties.fqdns) {
      Write-Host "$($ipconfig.properties.privateIPAddress) $($fqdn)"
      $recordName = $fqdn.split('.',2)[0]
      $dnsZone = $fqdn.split('.',2)[1]

      New-AzPrivateDnsRecordSet -Name $recordName -RecordType A -ZoneName $privateDnsZoneName `
        -ResourceGroupName $config.sre.network.vnet.rg -Ttl 600 `
        -PrivateDnsRecords (New-AzPrivateDnsRecordConfig -IPv4Address $ipconfig.properties.privateIPAddress)
    }
  }

}
