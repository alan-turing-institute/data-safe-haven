Import-Module Az

$environment = Read-Host -Prompt "Enter environment name ('test' or 'prod')"
$addressSpacePrefix = Read-Host -Prompt "Enter first three octets of address space e.g. 10.250.x"
$dsgId = Read-Host -Prompt "Enter DSG ID (usually a number e.g DSG9 = 9)"

$gitlabName = "GITLAB"
$gitlabVMSizeTest = "Standard_DS2_v2"
$gitlaVbMSizeProd = "Standard_DS2_v2"
$gitlabVMSize = If ($environment == "test") {$gitlabVMSizeTest} Else {$gitlabVMSizeProd}
$gitlabIP = $addressSpacePrefix + ".151"

$hackmdName = "HACKMD"
$hackmdVMSizeTest = "Standard_DS2_v2"
$hackmdVMSizeProd = "Standard_DS2_v2"
$hackmdVMSize = If ($environment == "test") {$hackmdVMSizeTest} Else {$hackmdVMSizeProd}
$hackmdIP = $addressSpacePrefix + ".152"

$vaultName = "dsg-management-" + $environment
$adminUser = "atiadmin"
$adminPassword = (Get-AzKeyVaultSecret -vaultName $vaultName -name "admin-dsg9-test-dc").SecretValueText
$securePassword = ConvertTo-SecureString $adminPassword –asplaintext –force
$vnetName = "DSG_DSGROUP" + $dsgId + "_VNET1"
$vnetResourceGroupName = "RG_DSG_VNET"
$vnetSubnet = "Subnet-Data"
$resourceGroupName = "RG_DSG_LINUX"

$params = @{
"GITLab Server Name" = $gitlabName
"GITLab VM Size" = $gitlabVMSize
"GITLab IP Address" = $gitlabIP
"HACKMD Server Name" = $hackmdName
"HACKMD VM Size" = $hackmdVMSize
"HACKMD IP Address" = $hackmdIP
"Administrator User" = $adminUser
"Administrator Password" = $securePassword
"Virtual Network Name" = $vnetName
"Virtual Network Resource Group" = $vnetResourceGroupName
"Virtual Network Subnet" = $vnetSubnet
}

Write-Output $params
New-AzResourceGroupDeployment -ResourceGroupName $resourceGroupName `
  -TemplateFile ./arm-templates/LinuxServers/linux-master-template.json @params -Verbose
