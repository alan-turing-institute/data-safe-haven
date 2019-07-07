param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$shmId
)



Import-Module Az
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/DsgConfig.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/GeneratePassword.psm1 -Force
Import-Module $PSScriptRoot/../../new_dsg_environment/dsg_deploy_scripts/GenerateSasToken.psm1 -Force

# Get DSG config
$config = Get-ShmFullConfig($shmId)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;

echo $config.npsRgName

New-AzResourceGroupDeployment -resourcegroupname "RG_SHM_NPS"`
        -templatefile "../arm_templates/shmnps/shmnps-template.json"`
        -Administrator_User atiadmin 

# TO RUN THIS SCRIPT (second is my personal subscription)
# ./setup_azure2.ps1 -SubscriptionId "ff4b0757-0eb8-4e76-a53d-4065421633a6" -DomainName = ""
