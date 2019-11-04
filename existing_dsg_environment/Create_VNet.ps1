# Login if required
# Login-AzureRmAccount

#VNet Name
$vnetname = "VNETNAME"  # Name of VNet to be created

#VNet configuration
$rg = "RESOURCEGROUP" # Resource group name
$region = "UK South" 
$subnetrds = "Subnet_RDS" # RDS subnet
$subnetdata = "Subnet_Data" # Data subnet
$subnetid = "Subnet_Identity" # Identity subnet
$subnetgw = "Subnet-Gateway" # VPN gateway subnet
$vnetprefix = "0.0.0.0/0" # Address space
$datasubprefix = "0.0.0.0/0" # Data subnet ip range
$idsubprefix = "0.0.0.0/0" # identity subnet ip range
$rdssubprefix = "0.0.0.0/0" # rds subnet ip range
$gwsubprefix = "0.0.0.0/0" # vpn gateway subnet range
$VPNClientAddressPool = "0.0.0.0/0" # vpn client address pool
$GWName = "GWNAME" # VPN gateway name
$GWIPName = "VPNPIP" # VPN gateway public IP
$GWIPconfName = "IPCONF" # VPN IP configuration


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

Read-Host -Prompt "Check that the subscription has been selected above, press enter key to continue or Ctrl+C to abort"


#Create Virtual Network Resource Group
write-Host -ForegroundColor Cyan "Creating resouce group...."
New-AzureRmResourceGroup -Name $rg -Location $region
write-Host -ForegroundColor Green "Done!"

#Create Subnet configuration
write-Host -ForegroundColor Cyan "Creating subnets...."
$rdssub = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetrds -AddressPrefix $rdssubprefix
$datasub = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetdata -AddressPrefix $datasubprefix
$idsub = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetid -AddressPrefix $idsubprefix
$gwsub = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetgw -AddressPrefix $gwsubprefix
write-Host -ForegroundColor Green "Done!"

#Create Virtual Network
write-Host -ForegroundColor Cyan "Creating virtual network...."
New-AzureRmVirtualNetwork -Name $vnetname -ResourceGroupName $rg -Location $region -AddressPrefix $vnetprefix -Subnet $rdssub, $datasub, $idsub, $gwsub
$vnet = Get-AzureRmVirtualNetwork -Name $vnetname -ResourceGroupName $rg
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name "Subnet-Gateway" -VirtualNetwork $vnet
write-Host -ForegroundColor Green "Done!"

#Create public IP address
write-Host -ForegroundColor Cyan "Creating public IP address...."
$pip = New-AzureRmPublicIpAddress -Name $GWIPName -ResourceGroupName $RG -Location $region -AllocationMethod Dynamic
$ipconf = New-AzureRmVirtualNetworkGatewayIpConfig -Name $GWIPconfName -Subnet $subnet -PublicIpAddress $pip
write-Host -ForegroundColor Green "Done!"

#Create VPN Gateway
write-Host -ForegroundColor Cyan "Creating virtual gateway..."
New-AzureRmVirtualNetworkGateway    -Name $GWName `
                                    -ResourceGroupName $RG `
                                    -Location $region `
                                    -IpConfigurations $ipconf `
                                    -GatewayType Vpn `
                                    -VpnType RouteBased `
                                    -EnableBgp $false `
                                    -GatewaySku VpnGw1 `
                                    -VpnClientProtocol "SSTP"
write-Host -ForegroundColor Green "Done!"

#Add VPN client address Pool
write-Host -ForegroundColor Cyan "Creating client address pool...."
$Gateway = Get-AzureRmVirtualNetworkGateway -ResourceGroupName $RG -Name $GWName
Set-AzureRmVirtualNetworkGateway -VirtualNetworkGateway $Gateway -VpnClientAddressPool $VPNClientAddressPool
write-Host -ForegroundColor Green "Done!"

#Upload certificate
write-Host -ForegroundColor Cyan "Uploading certificate...."
$P2SRootCertName = "DSG_P2S_RootCert.cer"
$filePathForCert = "PATHTOCERTFILE" # Path to certificate
$cert = new-object System.Security.Cryptography.X509Certificates.X509Certificate2($filePathForCert)
$CertBase64 = [system.convert]::ToBase64String($cert.RawData)
$p2srootcert = New-AzureRmVpnClientRootCertificate -Name $P2SRootCertName -PublicCertData $CertBase64
Add-AzureRmVpnClientRootCertificate -VpnClientRootCertificateName $P2SRootCertName -VirtualNetworkGatewayname $GWName -ResourceGroupName $RG -PublicCertData $CertBase64
write-Host -ForegroundColor Green "VNet and VPN Gateway Done!"