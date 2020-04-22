# Setup script that creates private endpoints to Azure resources that already
# exist and are listed in the 'privateEndpoints' element of the SRE configuration.

param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId
)

Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force

# Get the SRE config
# ------------------
$config = Get-SreConfig $sreId

# Temp test:
# Write-Output $config.sre.privateEndpoints

# Loop over the private endpoints in the configuration
# ----------------------------------------------------
Foreach ($pe in $config.sre.privateEndpoints) {

  # Temp test:
  # Write-Output $pe.subscriptionName

  # Switch to the subscription containing target resource to get the resource
  # -------------------------------------------------------------------------
  $_ = Set-AzContext -Subscription $pe.subscriptionName
  $resource = Get-AzResource -Name $pe.resourceName

  # Create the private endpoint
  # ---------------------------
  Add-LogMessage -Level Info "Creating private endpoint '$($pe.privateEndpointName)'"

  $privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "myConnection" `
    -PrivateLinkServiceId $sqlServer.ResourceId `
    -GroupId "sqlServer"

  # TODO FROM HERE.
  # $virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName  "myResourceGroup" -Name "MyVirtualNetwork"
  #
  # $subnet = $virtualNetwork `
  #   | Select -ExpandProperty subnets `
  #   | Where-Object  {$_.Name -eq 'mysubnet'}
  #
  # $privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName "myResourceGroup" `
  #   -Name "myPrivateEndpoint" `
  #   -Location "westcentralus" `
  #   -Subnet  $subnet`
  #   -PrivateLinkServiceConnection $privateEndpointConnection

}
