# Subscription IDs required and user performing the task needs to have access to other subscriptions and logged into both

# Safe Haven Management Subscription
$vNetA= Get-AzureRmVirtualNetwork -Name LOCALVNETNAME -ResourceGroupName VNETRESOURCE GROUP
        Add-AzureRmVirtualNetworkPeering `
        -Name 'PEER_TARGETNETWORKNAME' ` #VNET in DSG subscription
        -VirtualNetwork $vNetA `
        -RemoteVirtualNetworkId "/subscriptions/DSGSubscriptionId>/resourceGroups/VNETResourceGroup/providers/Microsoft.Network/virtualNetworks/TARGETNETWORKNAME"
        
        
# DSG Subscription
$vNetB = Get-AzureRmVirtualNetwork -Name LOCALVNETNAME -ResourceGroupName VNETRESOURCE GROUP
        Add-AzureRmVirtualNetworkPeering `
        -Name 'PEER_TARGETNETWORKNAME' ` #VNET in Safe Haven Mangement subscription
        -VirtualNetwork $vNetB `
        -RemoteVirtualNetworkId "/subscriptions/SafeHavenManagmentSubscriptionId>/resourceGroups/VNETResourceGroup/providers/Microsoft.Network/virtualNetworks/TARGETNETWORKNAME"
      
