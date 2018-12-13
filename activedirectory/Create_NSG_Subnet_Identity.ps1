#Resources
$resourceGroupName = "RG_DSG_VNET"
$location = "UKWest"
$region = "ukwest"
$nsgName = "NSG_MGMT_SUBNET_IDENTITY"

#Select subscription
write-Host -ForegroundColor Cyan "Select the correct subscription..."
$subscription = (
    Get-AzureRmSubscription |
    Sort-Object -Property Name |
    Select-Object -Property Name,Id |
    Out-GridView -OutputMode Single -Title 'Select an subscription'
).name

Select-AzureRmSubscription -SubscriptionName $subscription
write-Host -ForegroundColor Green "Ok, lets go!"

Read-Host -Prompt "Check that the subscription has been selected above, press any key to continue or Ctrl+C to abort"

# Create Network Security Group
$nsg = New-AzureRmNetworkSecurityGroup -Name "$nsgName" -ResourceGroupName $resourceGroupName -Location $location

$nsg = Get-AzureRmNetworkSecurityGroup -Name "$nsgName" -ResourceGroupName $resourceGroupName

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "RPC_endpoint_mapper" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol * `
                                       -Direction Inbound `
                                       -Priority 200 `
                                       -SourceAddressPrefix "10.250.248.0/24" `
                                       -SourcePortRange  * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 135
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "LDAP" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol TCP `
                                       -Direction Inbound `
                                       -Priority 201 `
                                       -SourceAddressPrefix "10.250.248.0/24","10.250.250.0/24"  `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 389
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "LDAP_Ping" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol UDP `
                                       -Direction Inbound `
                                       -Priority 202 `
                                       -SourceAddressPrefix "10.250.248.0/24","10.250.250.0/24"  `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 389
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "LDAP_over_SSL" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol TCP `
                                       -Direction Inbound `
                                       -Priority 203 `
                                       -SourceAddressPrefix "10.250.248.0/24"  `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 636
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "Global_catalog_LDAP" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol TCP `
                                       -Direction Inbound `
                                       -Priority 204 `
                                       -SourceAddressPrefix "10.250.248.0/24"  `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 3268
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "Global_catalog_LDAP_over_SSL" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol TCP `
                                       -Direction Inbound `
                                       -Priority 205 `
                                       -SourceAddressPrefix "10.250.248.0/24" `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 3269
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "DNS" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol * `
                                       -Direction Inbound `
                                       -Priority 206 `
                                       -SourceAddressPrefix "10.250.248.0/24"  `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 53
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "Kerberos" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol * `
                                       -Direction Inbound `
                                       -Priority 207 `
                                       -SourceAddressPrefix "10.250.248.0/24"  `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 88
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "SMB_over_IP_Microsoft-DS" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol * `
                                       -Direction Inbound `
                                       -Priority 208 `
                                       -SourceAddressPrefix "10.250.248.0/24"  `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 445
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "NetBIOS_name_service" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol * `
                                       -Direction Inbound `
                                       -Priority 209 `
                                       -SourceAddressPrefix VirtualNetwork `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 137
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "NetBIOS_datagram_service" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol UDP `
                                       -Direction Inbound `
                                       -Priority 210 `
                                       -SourceAddressPrefix VirtualNetwork `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 138
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "NetBIOS_session_service" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol TCP `
                                       -Direction Inbound `
                                       -Priority 211 `
                                       -SourceAddressPrefix VirtualNetwork `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 139
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "NetBIOS_session_service" `
                                       -Description "Active Directory Rule" `
                                       -Access Allow `
                                       -Protocol TCP `
                                       -Direction Inbound `
                                       -Priority 211 `
                                       -SourceAddressPrefix VirtualNetwork `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 139
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "Kerberos_Password_Change" `
                                       -Description "Kerberos Password Change" `
                                       -Access Allow `
                                       -Protocol * `
                                       -Direction Inbound `
                                       -Priority 213 `
                                       -SourceAddressPrefix VirtualNetwork `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 464
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "RADIUS_Authenitcation_RDS_to_NPS" `
                                       -Description "Allows RDS servers to connection to NPS server for MFA" `
                                       -Access Allow `
                                       -Protocol UDP `
                                       -Direction Inbound `
                                       -Priority 300 `
                                       -SourceAddressPrefix "10.250.249.250"  `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange "1812","1813"
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg

Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "Remote_Desktop_Connection" `
                                       -Description "Allows RDP connection to servers from P2S VPN" `
                                       -Access Allow `
                                       -Protocol TCP `
                                       -Direction Inbound `
                                       -Priority 400 `
                                       -SourceAddressPrefix "172.16.201.0/24"  `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix VirtualNetwork `
                                       -DestinationPortRange 3389
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg







Add-AzureRmNetworkSecurityRuleConfig   -NetworkSecurityGroup $nsg `
                                       -Name "Deny_All" `
                                       -Description "Block non-AD traffic" `
                                       -Access Deny `
                                       -Protocol * `
                                       -Direction Inbound `
                                       -Priority 3000 `
                                       -SourceAddressPrefix * `
                                       -SourcePortRange * `
                                       -DestinationAddressPrefix * `
                                       -DestinationPortRange *
Set-AzureRmNetworkSecurityGroup -NetworkSecurityGroup $nsg
