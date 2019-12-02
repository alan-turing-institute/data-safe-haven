#VNet Name
$vnetname = "SHM_VNET1"  #UPDATE NAME BEFORE RUNNING!

#VNet configuration
$rg = "RG_SHM_VNET"
$region = "UK South"
$subnetid = "Subnet-Identity"
$subnetweb = "Subnet-Web"
$subnetgw = "GatewaySubnet"

$vnetprefix = "10.251.0.0/21"
$idsubprefix = "10.251.0.0/24"
$websubprefix = "10.251.1.0/24"
$gwsubprefix = "10.251.7.0/27"
$VPNClientAddressPool = "172.16.201.0/24"
$GWName = "SHM_VNET1_GW"
$GWIPName = "SHM_VNET1_GW_PIP"
$GWIPconfName = "shmgwipconf"


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
$idsub = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetid -AddressPrefix $idsubprefix
$websub = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetweb -AddressPrefix $websubprefix
$gwsub = New-AzureRmVirtualNetworkSubnetConfig -Name $subnetgw -AddressPrefix $gwsubprefix
write-Host -ForegroundColor Green "Done!"

#Create Virtual Network
write-Host -ForegroundColor Cyan "Creating virtual network...."
New-AzureRmVirtualNetwork -Name $vnetname -ResourceGroupName $rg -Location $region -AddressPrefix $vnetprefix -Subnet $idsub, $websub, $gwsub
$vnet = Get-AzureRmVirtualNetwork -Name $vnetname -ResourceGroupName $rg
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name "GatewaySubnet" -VirtualNetwork $vnet
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
$P2SRootCertName = "ATISafeHaven-P2SRootCert.cer"
$filePathForCert = "ATISafeHaven-P2SRootCert.cer"
$cert = new-object System.Security.Cryptography.X509Certificates.X509Certificate2($filePathForCert)
$CertBase64 = [system.convert]::ToBase64String($cert.RawData)
$p2srootcert = New-AzureRmVpnClientRootCertificate -Name $P2SRootCertName -PublicCertData $CertBase64
Add-AzureRmVpnClientRootCertificate -VpnClientRootCertificateName $P2SRootCertName -VirtualNetworkGatewayname $GWName -ResourceGroupName $RG -PublicCertData $CertBase64
write-Host -ForegroundColor Green "VNet and VPN Gateway Done!"
