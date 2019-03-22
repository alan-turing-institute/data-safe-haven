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
$nsg = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.nsg.sessionHosts;
$sh1Nic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.rds.rg -Name $sh1NicName;
$sh2Nic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.rds.rg -Name $sh2NicName;

# Assign RDS Session Host NICs to RDS NSG
$sh1Nic.NetworkSecurityGroup = $nsg;
$sh1Nic | Set-AzNetworkInterface;

$sh2Nic.NetworkSecurityGroup = $nsg;
$sh2Nic | Set-AzNetworkInterface;

# Switch back to previous subscription
Set-AzContext -Context $prevContext;