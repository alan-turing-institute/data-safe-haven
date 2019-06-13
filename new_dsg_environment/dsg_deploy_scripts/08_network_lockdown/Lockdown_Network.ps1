param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext;
Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

Write-Host ("Locking down network configuration for DSG" + $config.dsg.id `
           + " (Tier " + $config.dsg.tier + "), hosted on subscription '" + `
           $config.dsg.subscriptionName + "'.")

# =======================================================================
# === Ensure RDS session hosts are bound to most restricted Linux NSG ===
# =======================================================================

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

# Wait a short while for NIC association to complete
Start-Sleep -Seconds 5
Write-Host ("   - Done: NICs associated with '" + $nsgSessionHosts.Name + "' NSG")
 @($nsgSessionHosts.NetworkInterfaces) | ForEach-Object{Write-Host ("     - " + $_.Id.Split("/")[-1])}

# ====================================================================
# === Ensure Webapp servers are bound to most restricted Linux NSG ===
# ====================================================================

# Set names of Network Security Group (NSG) and Network Interface Cards (NICs)
$gitlabNicName = $config.dsg.linux.gitlab.vmName + "_NIC1";
$hackMdNicName = $config.dsg.linux.hackmd.vmName + "_NIC1";

# Set Azure Network Security Group (NSG) and Network Interface Cards (NICs) objects
$nsgLinux = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.nsg;
$gitlabNic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.linux.rg -Name $gitlabNicName;
$hackMdNic = Get-AzNetworkInterface -ResourceGroupName $config.dsg.linux.rg -Name $hackMdNicName;
Write-Host (" - Associating Web App Servers with '" + $nsgLinux.Name + "' NSG")

# Assign Webapp server NICs to Linux VM NSG
$gitlabNic.NetworkSecurityGroup = $nsgLinux;
$_ = ($gitlabNic | Set-AzNetworkInterface);
$hackMdNic.NetworkSecurityGroup = $nsgLinux;
$_ = ($hackMdNic | Set-AzNetworkInterface);

# Wait a short while for NIC association to complete
Start-Sleep -Seconds 5
Write-Host ("   - Done: NICs associated with '" + $nsgLinux.Name + "' NSG")
@($nsgLinux.NetworkInterfaces) | ForEach-Object{Write-Host ("   -   " + $_.Id.Split("/")[-1])}

# ==================================================
# === Update RDS Gateway NSG to match DSG config ===
# ==================================================

# Update RDS Gateway NSG inbound access rule
$nsgGateway = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.nsg.gateway.name;
$httpsInRuleName = "HTTPS_In"
$httpsInRuleBefore = Get-AzNetworkSecurityRuleConfig -Name $httpsInRuleName -NetworkSecurityGroup $nsgGateway;

# Load allowed sources into an array, splitting on commas and trimming any whitespace from
# each item to avoid "invalid Address prefix" errors caused by extraneous whitespace
$allowedSources = ($config.dsg.rds.nsg.gateway.allowedSources.Split(',') | ForEach-Object{$_.Trim()})

Write-Host (" - Updating '" + $httpsInRuleName + "' rule on '" + $nsgGateway.name + "' NSG to '" `
            + $httpsInRuleBefore.Access  + "' access from '" + $allowedSources `
            + "' (was previously '" + $httpsInRuleBefore.SourceAddressPrefix + "')")
             
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

Write-Host ("   - Done: '" + $httpsInRuleName + "' on '" + $nsgGateway.name + "' NSG will now '" + $httpsInRuleAfter.Access `
            + "' access from '" + $httpsInRuleAfter.SourceAddressPrefix + "'")

# =======================================================
# === Update restricted Linux NSG to match DSG config ===
# =======================================================

# Update RDS Gateway NSG inbound access rule
$nsgLinux = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.nsg;
$internetOutRuleName = "Internet_Out"
$internetOutRuleBefore = Get-AzNetworkSecurityRuleConfig -Name $internetOutRuleName -NetworkSecurityGroup $nsgLinux;

# Outbound access to Internet is Allowed for Tier 0 and 1 but Denied for Tier 2 and above
If ($config.dsg.tier -in 0,1){
  $access = "Allow"
}
Else {
  $access = "Deny"
}
$allowedSources = ($config.dsg.rds.nsg.gateway.allowedSources.Split(',') | ForEach-Object{$_.Trim()})

Write-Host (" - Updating '" + $internetOutRuleName + "' rule on '" + $nsgLinux.name + "' NSG to '" `
            + $access  + "' access to '" + $internetOutRuleBefore.DestinationAddressPrefix `
            + "' (was previously '" + $internetOutRuleBefore.Access + "')")
             
$nsgLinuxInternetOutRuleParams = @{
  Name = $internetOutRuleName
  NetworkSecurityGroup = $nsgLinux
  Description = "Control outbound internet access from user accessible VMs"
  Access = $access
  Direction = "Outbound"
  SourceAddressPrefix = "VirtualNetwork"
  Protocol = "*"
  SourcePortRange = "*"
  DestinationPortRange = "*"
  DestinationAddressPrefix = "Internet"
  Priority = "4000"
}

# Update rule and NSG (both are required)
$_ = Set-AzNetworkSecurityRuleConfig @nsgLinuxInternetOutRuleParams;
$_ = Set-AzNetworkSecurityGroup -NetworkSecurityGroup $nsgLinux;

# Confirm update has being successfully applied
$internetOutRuleAfter = Get-AzNetworkSecurityRuleConfig -Name $internetOutRuleName -NetworkSecurityGroup $nsgLinux;

Write-Host ("   - Done: '" + $internetOutRuleName + "' on '" + $nsgLinux.name + "' NSG will now '" + $internetOutRuleAfter.Access `
            + "' access to '" + $internetOutRuleAfter.DestinationAddressPrefix + "'")


# Switch back to previous subscription
Set-AzContext -Context $prevContext;