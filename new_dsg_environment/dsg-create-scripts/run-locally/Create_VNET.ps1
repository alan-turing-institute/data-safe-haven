Import-Module Az

$addressSpacePrefix12 = Read-Host -Prompt "Enter first two octets of address space e.g. 10.250"
$addressSpacePrefix3 = Read-Host -Prompt "Enter the third octet of address space e.g. the x in 10.250.x"
$dsgId = Read-Host -Prompt "Enter DSG ID (usually a number e.g DSG9 = 9)"
$resourceGroupName = "RG_DSG_VNET"

$virtualNetworkName = "DSG_DSGROUP" + $dsgId + "_VNET1"
$addressSpacePrefix = $addressSpacePrefix12 + "." + $addressSpacePrefix3
$virtualNetworkAddressSpace = $addressSpacePrefix + ".0/21"
$subnetIdentityPrefix = $addressSpacePrefix + ".0/24"
$subnetRdsPrefix = $addressSpacePrefix12 + "." + ([int]$addressSpacePrefix3 + 1) + ".0/24"
$subnetDataPrefix = $addressSpacePrefix12 + "." + ([int]$addressSpacePrefix3 + 2) + ".0/24"
$subnetGatewayPrefix =  $addressSpacePrefix12 + "." + ([int]$addressSpacePrefix3 + 7) + ".0/27"
$dnsServerIP =  $addressSpacePrefix + ".250"
$certBytes = Get-Content "./secrets/DSG_P2S_RootCert.cer" -AsByteStream
$cert = [System.Convert]::ToBase64String($certBytes)


$params = @{
 "Virtual Network Name" = $virtualNetworkName
 "P2S VPN Certificate" = $cert
 "Virtual Network Address Space" = $virtualNetworkAddressSpace
 "Subnet-Identity Address Prefix" = $subnetIdentityPrefix
 "Subnet-RDS Address Prefix" = $subnetRdsPrefix
 "Subnet-Data Address Prefix" = $subnetDataPrefix
 "Subnet-Gateway Address Prefix" = $subnetGatewayPrefix
 "DNS Server IP Address" = $dnsServerIP
}

# Write-Output $params

New-AzResourceGroup -Name $resourceGroupName -Location uksouth
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
  -TemplateFile ./arm-templates/VNet/vnet-master-template.json @params -Verbose
