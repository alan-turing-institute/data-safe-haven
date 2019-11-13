param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/GenerateSasToken.psm1 -Force

# Get DSG config
$config = Get-ShmFullConfig($shmId)

# Set VM Default Size
$vmSize = "Standard_DS2_v2"

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;

New-AzResourceGroup -Name $config.nps.rg -Location $config.location
$dcAdminUsername = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcAdminUsername).SecretValueText;
$dcAdminPassword = (Get-AzKeyVaultSecret -vaultName $config.keyVault.name -name $config.keyVault.secretNames.dcAdminPassword).SecretValueText;
New-AzResourceGroupDeployment -resourcegroupname $config.nps.rg`
        -templatefile "$PSScriptRoot/../arm_templates/shmnps/shmnps-template.json"`
        -Administrator_User $dcAdminUsername  `
        -Administrator_Password (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force) `
        -Virtual_Network_Resource_Group $config.network.vnet.rg `
        -Domain_Name $config.domain.fqdn `
        -VM_Size $vmSize `
        -Virtual_Network_Name $config.network.vnet.name `
        -Virtual_Network_Subnet $config.network.subnets.identity.name `
        -NPS_VM_Name $config.nps.vmName `
        -NPS_Host_Name $config.nps.hostname `
        -NPS_IP_Address $config.nps.ip `
        -OU_Path $config.domain.serviceServerOuPath `
        -Verbose;

# Switch back to original subscription
Set-AzContext -Context $prevContext;