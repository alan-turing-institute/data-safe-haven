# Setup script that creates a storage account and related private endpoint if in the same subscription
# or only the private endpoint to already existing resources in other subscriptions.

param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId,
  [Parameter(Position=1, Mandatory = $false, HelpMessage = "Used to force the update of DNS record")]
  [switch]$dnsForceUpdate
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
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

	  # Create two blob container: ingress, which will have associated two differet SAS tokens with different permissions
	  $ctx = $storageAccount.Context
	  New-AzStorageContainer -Name "ingress" -Context $ctx

	  $resource = Get-AzResource -Name $sa.accountName -ExpandProperties
	  $accountId = $resource.ResourceId
	  Add-LogMessage -Level Info "The storage account '$accountId' has been created in the subscription '$($sa.subscriptionName)'"


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

# Create the ingress SAS token and store them in a secret



$accountKeys = Get-AzStorageAccountKey -ResourceGroupName $rg -Name $sa.accountName

$storageContext = New-AzStorageContext -StorageAccountName $sa.accountName -StorageAccountKey $accountKeys[0].Value
$start = [System.DateTime]::Now.AddDays($sa.startAccess)
$end = [System.DateTime]::Now.AddDays($sa.endAccess)

$ingressSAS = New-AzStorageContainerSASToken -Name "ingress" -Context $storageContext -Permission "rlw" -StartTime $start -ExpiryTime $end


# Ensure the keyvault exists and set its access policies
# ------------------------------------------------------
# -----------------------------------------
Add-LogMessage -Level Info "Ensuring that secrets exist in key vault '$($config.sre.keyVault.name)'..."

$_ = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.storageIngressSAS -DefaultValue "$ingressSAS"

if ($?) {
Add-LogMessage -Level Success "Uploading the ingressSAS succeeded"
} else {
       Add-LogMessage -Level Fatal "Uploading the ingressSAS failed!"
      }



# Create the private endpoint
# ---------------------------

$privateEndpointName = $sa.accountName + "-endpoint"


$privateDnsZoneName = $($sa.accountName +"." + $sa.PrivateLinkServiceConnectionGroupId+ ".core.windows.net").ToLower()
$privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$($privateEndpointName)ServiceConnection" `
-PrivateLinkServiceId $accountId `
-GroupId $sa.PrivateLinkServiceConnectionGroupId

$virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name

$subnet = $virtualNetwork `
| Select -ExpandProperty subnets `
| Where-Object  {$_.Name -eq $config.sre.network.subnets.data.name}

$privateEndpoint = Get-AzPrivateEndpoint -name $privateEndpointName

if (-not $privateEndpoint){
Add-LogMessage -Level Info "Creating private endpoint '$($privateEndpointName)' to resource '$($sa.accountName)'"
$privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $config.sre.network.vnet.rg `
-Name $privateEndpointName `
-Location $config.sre.Location `
-Subnet $subnet `
-PrivateLinkServiceConnection $privateEndpointConnection}
$privateip = (Get-AzNetworkInterface -Resourceid $($privateEndpoint.NetworkInterfaces.id)).IpConfigurations[0].PrivateIpAddress

Add-LogMessage -Level Info "Setting up DNS Zone"

$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName




$params = @{
    ZoneName = $privateDnsZoneName
    ipaddress = $privateip
    update  =  ($dnsForceUpdate ? "force" : "non forced")



}

$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_storage" "set_dns_zone.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -vmName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName
