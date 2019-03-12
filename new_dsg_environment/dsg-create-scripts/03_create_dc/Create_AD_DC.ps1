Import-Module Az

$environment = Read-Host -Prompt "Enter environment name ('test' or 'prod')"
$addressSpacePrefix = Read-Host -Prompt "Enter first three octets of address space e.g. 10.250.x"
$dsgId = Read-Host -Prompt "Enter DSG ID (usually a number e.g DSG9 = 9)"
$artifactSasToken = Read-Host -Prompt "Paste an SAS token with blob object read access for the 'dsgartifacts' storage account"

$resourceGroupName = "RG_DSG_DC"
$dcName = "DSG" + $dsgId + "DC"
$vmSize = "Standard_DS2_v2"
$ipAddress = $addressSpacePrefix + ".250"
$vaultName = "dsg-management-" + $environment
$adminUser = "atiadmin"
$adminPassword = (Get-AzKeyVaultSecret -vaultName $vaultName -name "admin-dsg9-test-dc").SecretValueText
$domainName = "DSGROUP" + $dsgId + ".CO.UK"

$vnetName = "DSG_DSGROUP" + $dsgId + "_VNET1"
$vnetResourceGroupName = "RG_DSG_VNET"
$vnetSubnet = "Subnet-Identity"
$artifactLocation = "https://dsgxartifacts.blob.core.windows.net"

$params = @{
 "DC Name" = $dcName
 "VM Size" = $vmSize
 "IP Address" = $ipAddress
 "Administrator User" = $adminUser
 "Administrator Password" = $adminPassword
 "Virtual Network Name" = $vnetName
 "Virtual Network Resource Group" = $vnetResourceGroupName
 "Virtual Network Subnet" = $vnetSubnet
 "Artifacts Location" = $artifactLocation
 "Artifacts Location SAS Token" = $artifactSasToken
 "Domain Name" = $domainName
}

Write-Output $params

New-AzResourceGroup -Name $resourceGroupName -Location uksouth
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
  -TemplateFile ./arm-templates/DCServer/dc-master-template.json @params -Verbose
