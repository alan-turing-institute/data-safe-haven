Import-Module Az

$environment = Read-Host -Prompt "Enter environment name ('test' or 'prod')"
$addressSpacePrefix12 = Read-Host -Prompt "Enter first two octets of address space e.g. 10.250"
$addressSpacePrefix3 = Read-Host -Prompt "Enter the third octet of address space e.g. the x in 10.250.x"
$dsgId = Read-Host -Prompt "Enter DSG ID (usually a number e.g DSG9 = 9)"

# General parameters
$addressSpacePrefix = $addressSpacePrefix12 + "." + ([int]$addressSpacePrefix3 + 1)
$resourceGroupName = "RG_DSG_RDS"
$domainName = "DSGROUP" + $dsgId + ".CO.UK"
$adminUser = "atiadmin"
$vaultName = "dsg-management-" + $environment
$adminPasswordSecretName = "dsg9-dc-admin-password"
$adminPassword = (Get-AzKeyVaultSecret -vaultName $vaultName -name $adminPasswordSecretName).SecretValueText

# RDS Gateway parameters
$rdsGatewayName = "RDS"
$rdsGatewayVmSize = "Standard_DS2_v2"
$rdsGatewayIpAddress = $addressSpacePrefix + ".250"

# RDS Session host parameters
$rdsHostVmSize = "Standard_DS2_v2"

$rdsHost1Name = "RDSSH1"
$rdsHost1IpAddress = $addressSpacePrefix + ".249"

$rdsHost2Name = "RDSSH2"
$rdsHost2IpAddress = $addressSpacePrefix + ".248"

# Virtual network parameters
$vnetName = "DSG_DSGROUP" + $dsgId + "_VNET1"
$vnetResourceGroupName = "RG_DSG_VNET"
$vnetSubnet = "Subnet-RDS"

$params = @{
 "RDS Gateway Name" = $rdsGatewayName
 "RDS Gateway VM Size" = $rdsGatewayVmSize
 "RDS Gateway IP Address" = $rdsGatewayIpAddress
 "RDS Session Host 1 Name" = $rdsHost1Name
 "RDS Session Host 1 VM Size" = $rdsHostVmSize
 "RDS Session Host 1 IP Address" = $rdsHost1IpAddress
 "RDS Session Host 2 Name" = $rdsHost2Name
 "RDS Session Host 2 VM Size" = $rdsHostVmSize
 "RDS Session Host 2 IP Address" = $rdsHost2IpAddress
 "Administrator User" = $adminUser
 "Administrator Password" = $adminPassword
 "Virtual Network Name" = $vnetName
 "Virtual Network Resource Group" = $vnetResourceGroupName
 "Virtual Network Subnet" = $vnetSubnet
 "Domain Name" = $domainName
}

Write-Output $params

New-AzResourceGroup -Name $resourceGroupName -Location uksouth
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
  -TemplateFile ./arm-templates/RDSServers/rds-master-template.json @params -Verbose
