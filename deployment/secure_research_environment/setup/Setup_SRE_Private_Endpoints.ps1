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

  # Switch to the subscription containing the target resource
  # ---------------------------------------------------------
  $_ = Set-AzContext -Subscription $pe.subscriptionName
  $resource = Get-AzResource -Name $pe.resourceName

  # Switch to the SRE subscription
  # ------------------------------
  $_ = Set-AzContext -Subscription $config.sre.subscriptionName

  # Create the private endpoint
  # ---------------------------
  Add-LogMessage -Level Info "Creating private endpoint '$($pe.privateEndpointName)' to resource '$($pe.resourceName)'"

  $privateEndpointConnection = New-AzPrivateLinkServiceConnection -Name "$($pe.privateEndpointName)ServiceConnection" `
    -PrivateLinkServiceId $resource.ResourceId `
    -GroupId $pe.PrivateLinkServiceConnectionGroupId

  $virtualNetwork = Get-AzVirtualNetwork -ResourceGroupName  $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name

  $subnet = $virtualNetwork `
    | Select -ExpandProperty subnets `
    | Where-Object  {$_.Name -eq $config.sre.network.subnets.data.name}

  # Write-Output $subnet.Name

  $privateEndpoint = New-AzPrivateEndpoint -ResourceGroupName $config.sre.network.vnet.rg `
    -Name $pe.privateEndpointName `
    -Location $config.sre.Location `
    -Subnet $subnet `
    -PrivateLinkServiceConnection $privateEndpointConnection
}
