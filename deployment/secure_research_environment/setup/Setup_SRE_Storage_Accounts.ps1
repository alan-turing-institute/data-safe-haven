
param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId
)

Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------
$config = Get-SreConfig $sreId
$subscriptionName = $config.sre.subscriptionName

$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName

# Loop over the storage accounts in the configuration
# ----------------------------------------------------

Foreach ($sa in $config.sre.storageAccounts) {

$availability = Get-AzStorageAccountNameAvailability -Name $sa.accountName

if ($sa.subscriptionName -eq $subscriptionName) {

  if($availability.NameAvailable){

     $rg = $config.sre.dataserver.rg
  
    # Create database resource group if it does not exist
    # ---------------------------------------------------

    Add-LogMessage -Level Info "Creating storage account '$($sa.accountName)' under '$($rg)' in the subscription '$($sa.subscriptionName)'"

    $_ = Deploy-ResourceGroup -Name $rg -Location $config.sre.location

    # Create storage account 
    New-AzStorageAccount -ResourceGroupName $rg -Name $sa.accountName -Location $config.sre.location  -SkuName Standard_RAGRS -Kind StorageV2
    Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $rg -Name $sa.accountName -DefaultAction Deny
  }  
  else {
    Add-LogMessage -Level Info "The storage account '$($sa.accountName)' already exists in the subscription '$($sa.subscriptionName)'"

  }
}
else {
if($availability.NameAvailable){

  Add-LogMessage -Level Info "The storage account '$($sa.accountName)' in the subscription '$($sa.subscriptionName)' does not exist yet"
  exit
}

else{
if
($availability.Reason -eq "AlreadyExists")
{
  Add-LogMessage -Level Info "The storage account '$($sa.accountName)' already exists in the subscription '$($sa.subscriptionName)'"
 
}

else {
   write-host("The storage account belongs to a different subscription, and we encountered the following issue", $availability.Reason)
   exit

}
}
}

  $privateEndpointName = $sa.accountName + "-endpoint"
  $privateDnsZoneName = $sa.accountName + ".blob.core.windows.net"


  # Create the private endpoint
  # ---------------------------
  Add-LogMessage -Level Info "Creating private endpoint '$($privateEndpointName)' to resource '$($sa.accountName)'"

  $privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$($privateEndpointName)ServiceConnection" `
    -PrivateLinkServiceId $sa.accountId `
    -GroupId $sa.PrivateLinkServiceConnectionGroupId

  $virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name

  $subnet = $virtualNetwork `
    | Select -ExpandProperty subnets `
    | Where-Object  {$_.Name -eq $config.sre.network.subnets.data.name}

  $privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $config.sre.network.vnet.rg `
    -Name $privateEndpointName `
    -Location $config.sre.Location `
    -Subnet $subnet `
    -PrivateLinkServiceConnection $privateEndpointConnection

  # Create a Private DNS Zone
  # ----------------------------
    
  Add-LogMessage -Level Info "Creating private DNS zone '$($privateDnsZoneName)'"
  $zone = New-AzPrivateDnsZone -ResourceGroupName $config.sre.network.vnet.rg `
    -Name $privateDnsZoneName

  $privateDnsVirtualNetworkLinkName = "$($sa.accountName)VirtualNetworkLink"
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