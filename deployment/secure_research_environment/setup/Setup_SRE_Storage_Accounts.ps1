# Setup script that creates a storage account and related private endpoint if in the same subscription
# or only the private endpoint to already existing resources in other subscriptions.

param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force

# Get config and set context
# ------------------
$config = Get-SreConfig $sreId
$subscriptionName = $config.sre.subscriptionName

$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName

# Loop over the storage accounts in the configuration
# ----------------------------------------------------

$sa = $config.sre.storageAccount

# check if it is available or not
$availability = Get-AzStorageAccountNameAvailability -Name $sa.accountName

if ($sa.subscriptionName -eq $subscriptionName) {

	# the resource group location of the storage account
	$rg = $config.sre.dataserver.rg


	if($availability.NameAvailable){

	  # Create storage account if it does not exist
	  # ---------------------------------------------------
	  Add-LogMessage -Level Info "Creating storage account '$($sa.accountName)' under '$($rg)' in the subscription '$($sa.subscriptionName)'"

	  $_ = Deploy-ResourceGroup -Name $rg -Location $config.sre.location

	  # Create storage account 
	  $storageAccount = New-AzStorageAccount -ResourceGroupName $rg -Name $sa.accountName -Location $config.sre.location  -SkuName Standard_RAGRS -Kind StorageV2

	  # Deny network access
	  Update-AzStorageAccountNetworkRuleSet -ResourceGroupName $rg -Name $sa.accountName -DefaultAction Deny

	  # Create two blob container: ingress and egress, which will have associated two differet SAS tokens with different permissions
	  $ctx = $storageAccount.Context
	  New-AzStorageContainer -Name "ingress" -Context $ctx 
	  New-AzStorageContainer -Name "egress" -Context $ctx 

	  $resource = Get-AzResource -Name $sa.accountName -ExpandProperties
	  $accountId = $resource.ResourceId


	}  
	else {
	  Add-LogMessage -Level Info "The storage account '$($sa.accountName)' already exists in the subscription '$($sa.subscriptionName)'"
	  	$resource = Get-AzResource -Name $sa.accountName -ExpandProperties
	    $accountId = $resource.ResourceId
	}


	}
else {

	if($availability.NameAvailable){

	  # exit in case the storage account doesn't exist under the external subscription
	  Add-LogMessage -Level Info "The storage account '$($sa.accountName)' in the subscription '$($sa.subscriptionName)' does not exist yet"
	  exit
	}

	else {


	  if($availability.Reason -eq "AlreadyExists")
	  {
	    # read the account id from the config
	    Add-LogMessage -Level Info "The storage account '$($sa.accountName)' already exists in the subscription '$($sa.subscriptionName)'"
	    $accountId = $sa.accountId
	    $rg = $sa.rg

	   
	  }

	  else {
	    # otherwise report which issue was encountered
	     write-host("The storage account belongs to a different subscription, and we encountered the following issue", $availability.Reason)
	     exit

	  }
	}
}

# Create the ingress and egress SAS token and store them in a secret



$accountKeys = Get-AzStorageAccountKey -ResourceGroupName $rg -Name $sa.accountName

$storageContext = New-AzStorageContext -StorageAccountName $sa.accountName -StorageAccountKey $accountKeys[0].Value
$start = [System.DateTime]::Now.AddDays($sa.startAccess)
$end = [System.DateTime]::Now.AddDays($sa.endAccess)

#$ingressSAS = New-AzStorageAccountSASToken -Service $sa.PrivateLinkServiceConnectionGroupId -Context $storageContext -ResourceType Container  -Permission "rwl" -StartTime $start -ExpiryTime $end 

$ingressSAS = New-AzStorageContainerSASToken -Name "ingress" -Context $storageContext -Permission "rwl" -StartTime $start -ExpiryTime $end 
$ingressSAS
exit

$egressSAS = New-AzStorageAccountSASToken -Service $sa.PrivateLinkServiceConnectionGroupId -Context $storageContext -ResourceType Container  -Permission "rwl" -StartTime $start -ExpiryTime $end 




# Ensure the keyvault exists and set its access policies
# ------------------------------------------------------
$_ = Deploy-KeyVault -Name $config.sre.keyVault.name -ResourceGroupName $config.sre.keyVault.rg -Location $config.sre.location
Set-KeyVaultPermissions -Name $config.sre.keyVault.name -GroupName $config.sre.adminSecurityGroupName

# -----------------------------------------
Add-LogMessage -Level Info "Ensuring that secrets exist in key vault '$($config.keyVault.name)'..."

$_ = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.storageIngressSAS
if ($?) {
  Add-LogMessage -Level Success "AD sync password exists"
} else {
  Add-LogMessage -Level Fatal "Failed to create AD sync password!"
}

$_ = Set-AzKeyVaultSecret -VaultName $config.sre.keyVault.Name -Name $config.sre.keyVault.secretNames.storageIngressSAS -SecretValue (ConvertTo-SecureString "$ingressSAS" -AsPlainText -Force)
if ($?) {
Add-LogMessage -Level Success "Uploading the ingressSAS succeeded"
} else {
       Add-LogMessage -Level Fatal "Uploading the ingressSAS failed!"
      }


$_ = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.storagegressSAS
if ($?) {
  Add-LogMessage -Level Success "AD sync password exists"
} else {
  Add-LogMessage -Level Fatal "Failed to create AD sync password!"
}

$_ = Set-AzKeyVaultSecret -VaultName $config.sre.keyVault.Name -Name $config.sre.keyVault.secretNames.storagegressSAS -SecretValue (ConvertTo-SecureString "$egressSAS" -AsPlainText -Force)
if ($?) {
Add-LogMessage -Level Success "Uploading the egressSAS succeeded"
} else {
       Add-LogMessage -Level Fatal "Uploading the egressSAS failed!"
      }


# Create the private endpoint
# ---------------------------

$privateEndpointName = $sa.accountName + "-endpoint"

Add-LogMessage -Level Info "Creating private endpoint '$($privateEndpointName)' to resource '$($sa.accountName)'"

$privateDnsZoneName = $($sa.accountName +"." + $sa.PrivateLinkServiceConnectionGroupId+ ".core.windows.net").ToLower()
$privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$($privateEndpointName)ServiceConnection" `
-PrivateLinkServiceId $accountId `
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


