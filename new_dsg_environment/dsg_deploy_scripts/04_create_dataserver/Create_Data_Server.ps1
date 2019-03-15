Import-Module Az

$environment = Read-Host -Prompt "Enter environment name ('test' or 'prod')"
# $addressSpacePrefix = Read-Host -Prompt "Enter first three octets of address space e.g. 10.250.x"
$addressSpacePrefix12 = Read-Host -Prompt "Enter first two octets of address space e.g. 10.250"
$addressSpacePrefix3 = Read-Host -Prompt "Enter the third octet of address space e.g. the x in 10.250.x"
$addressSpacePrefix = $addressSpacePrefix12 + "." + ([int]$addressSpacePrefix3 + 2)
$dsgId = Read-Host -Prompt "Enter DSG ID (usually a number e.g DSG9 = 9)"

$dsName = "DATASERVER" # "DSG" + $dsgId + "DS"
$vaultName = "dsg-management-" + $environment
$adminUser = "atiadmin"
$adminPassword = (Get-AzKeyVaultSecret -vaultName $vaultName -name "dsg9-dc-admin-password").SecretValueText
$securePassword = ConvertTo-SecureString $adminPassword –asplaintext –force
$vnetName = "DSG_DSGROUP" + $dsgId + "_VNET1"
$vnetResourceGroupName = "RG_DSG_VNET"
$vnetSubnet = "Subnet-Data"
$domainName = "DSGROUP" + $dsgId + ".CO.UK"
$ipAddress = $addressSpacePrefix + ".100"
$vmSize = "Standard_DS2_v2"
$vmSizeTest = "Standard_DS2_v2"
$vmSizeProd = "Standard_DS2_v2"
$vmSize = If ($environment == "test") {$vmSizeTest} Else {$vmSizeProd}
$resourceGroupName = "RG_DSG_RDS"


$params = @{
"Data Server Name" = $dsName
"Domain Name" = $domainName
"VM Size" = $vmSize
"IP Address" = $ipAddress
"Administrator User" = $adminUser
"Administrator Password" = $securePassword
"Virtual Network Name" = $vnetName
"Virtual Network Resource Group" = $vnetResourceGroupName
"Virtual Network Subnet" = $vnetSubnet
}

Write-Output $params

# New-AzResourceGroup -Name $resourceGroupName -Location uksouth
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
  -TemplateFile ./arm-templates/DataServer/dataserver-master-template.json @params -Verbose
