param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext;
Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# === Lock down RDS VMs ===

# Set names of Network Security Group (NSG) and Network Interface Cards (NICs)
$sh1NicName = $config.dsg.rds.sessionHost1.vmName + "_NIC1";
$sh2NicName = $config.dsg.rds.sessionHost2.vmName + "_NIC1";

# Set Azure Network Security Group (NSG) and Network Interface Cards (NICs) objects
$nsgSessionHosts = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.nsg.sessionHosts.name;
$sh1Nic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.rds.rg -Name $sh1NicName;
$sh2Nic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.rds.rg -Name $sh2NicName;

# Assign RDS Session Host NICs to Session Hosts NSG
Write-Host (" - Associating RDS Session Hosts with '" + $nsgSessionHosts.Name + "' NSG")
$sh1Nic.NetworkSecurityGroup = $nsgSessionHosts;
$_ = ($sh1Nic | Set-AzNetworkInterface);
$sh2Nic.NetworkSecurityGroup = $nsgSessionHosts;
$_ = ($sh2Nic | Set-AzNetworkInterface);

Write-Host (" - NICs associated with '" + $nsgSessionHosts.Name + "'NSG")
 @($nsgSessionHosts.NetworkInterfaces) | ForEach-Object{Write-Host ("   - " + $_.Id.Split("/")[-1])}

# Update RDS Gateway NSG inbound access rule
$nsgGateway = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.nsg.gateway.name;
$httpsInRuleName = "HTTPS_In"
$httpsInRuleBefore = Get-AzNetworkSecurityRuleConfig -Name $httpsInRuleName -NetworkSecurityGroup $nsgGateway;

# Load allowed sources into an array, splitting on commas and trimming any whitespace from
# each item to avoid "invalid Address prefix" errors caused by extraneous whitespace
$allowedSources = ($config.dsg.rds.nsg.gateway.allowedSources.Split(',') | ForEach-Object{$_.Trim()})

Write-Host (" - Updating '" + $httpsInRuleName + "' rule source address prefix from '" + $httpsInRuleBefore.SourceAddressPrefix `
             + "' to '" + $allowedSources + "' on '" + $nsgGateway.name + "' NSG")
             
$nsgGatewayHttpsInRuleParams = @{
  Name = $httpsInRuleName
  NetworkSecurityGroup = $nsgGateway
  Description = "Allow HTTPS inbound to RDS server"
  Access = "Allow"
  Direction = "Inbound"
  SourceAddressPrefix = $allowedSources
  Protocol = "TCP"
  SourcePortRange = "*"
  DestinationPortRange = "443"
  DestinationAddressPrefix = "*"
  Priority = "101"
}

# Update rule and NSG (both are required)
$_ = Set-AzNetworkSecurityRuleConfig @nsgGatewayHttpsInRuleParams;
$_ = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgGateway;

# Confirm update has being successfully applied
$httpsInRuleAfter = Get-AzNetworkSecurityRuleConfig -Name $httpsInRuleName -NetworkSecurityGroup $nsgGateway;

Write-Host (" - '" + $httpsInRuleName + "' rule source address prefix is now '" + $httpsInRuleAfter.SourceAddressPrefix `
            + "' on '" + $nsgGateway.name + "' NSG")

# === Lock down Web App servers ===

# Set names of Network Security Group (NSG) and Network Interface Cards (NICs)
$gitlabNicName = $config.dsg.linux.gitlab.vmName + "_NIC1";
$hackMdNicName = $config.dsg.linux.hackmd.vmName + "_NIC1";

# Set Azure Network Security Group (NSG) and Network Interface Cards (NICs) objects
$nsgLinux = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.nsg;
$gitlabNic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.linux.rg -Name $gitlabNicName;
$hackMdNic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.linux.rg -Name $hackMdNicName;
Write-Host (" - Associating Web App Servers with '" + $nsgLinux.Name + "' NSG")

# Assign RDS Session Host NICs to Linux VM NSG
$gitlabNic.NetworkSecurityGroup = $nsgLinux;
$_ = ($gitlabNic | Set-AzNetworkInterface);

$hackMdNic.NetworkSecurityGroup = $nsgLinux;
$_ = ($hackMdNic | Set-AzNetworkInterface);

Write-Host (" - NICs associated with '" + $nsgLinux.Name + "'NSG")
@($nsgLinux.NetworkInterfaces) | ForEach-Object{Write-Host ("   - " + $_.Id.Split("/")[-1])}


# Switch back to previous subscription
Set-AzContext -Context $prevContext;