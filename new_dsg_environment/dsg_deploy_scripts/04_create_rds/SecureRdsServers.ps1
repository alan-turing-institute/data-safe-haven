param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to management subscription
$prevContext = Get-AzContext;
Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Set names of Network Security Group (NSG) and Network Interface Cards (NICs)
$sh1NicName = $config.dsg.rds.sessionHost1.vmName + "_NIC1";
$sh2NicName = $config.dsg.rds.sessionHost2.vmName + "_NIC1";

# Set Azure Network Security Group (NSG) and Network Interface Cards (NICs) objects
$nsgSessionHosts = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.nsg.sessionHosts.name;
$sh1Nic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.rds.rg -Name $sh1NicName;
$sh2Nic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.rds.rg -Name $sh2NicName;

# Assign RDS Session Host NICs to Session Hosts NSG
$sh1Nic.NetworkSecurityGroup = $nsgSessionHosts;
$sh1Nic | Set-AzNetworkInterface;
$sh2Nic.NetworkSecurityGroup = $nsgSessionHosts;
$sh2Nic | Set-AzNetworkInterface;

# Update RDS Gateway NSG ibbound access rule
$nsgGateway = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.nsg.gateway.name;

$httpsInRuleName = "HTTPS_In"
Write-Host ($httpsInRuleName + " rule for " + $nsgGateway.Name + " before update:")
Write-Host "====="
Get-AzNetworkSecurityRuleConfig -Name $httpsInRuleName -NetworkSecurityGroup $nsgGateway

$allowedSources = $config.dsg.rds.nsg.gateway.allowedSources.Split(',')
Write-Host $allowedSources
$nsgGatewayHttpsInRuleParams = @{
  Name = $httpsInRuleName
  NetworkSecurityGroup = $nsgGateway
  Description = "Allow HTTPS inbound to RDS server"
  Access = "Allow"
  Direction = "Inbound"
  SourceAddressPrefix = "193.60.220.253", "193.60.220.240"
  Protocol = "TCP"
  SourcePortRange = "*"
  DestinationPortRange = "443"
  DestinationAddressPrefix = "*"
  Priority = "101"
}

Write-Host ("Updating " + $httpsInRuleName + " rule for " + $nsgGateway.Name + ":")
Write-Host "====="
Set-AzNetworkSecurityRuleConfig @nsgGatewayHttpsInRuleParams
Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgGateway

Write-Host ($httpsInRuleName + " rule for " + $nsgGateway.Name + " after update:")
Write-Host "====="
Get-AzNetworkSecurityRuleConfig -Name $httpsInRuleName -NetworkSecurityGroup $nsgGateway

# Switch back to previous subscription
Set-AzContext -Context $prevContext;