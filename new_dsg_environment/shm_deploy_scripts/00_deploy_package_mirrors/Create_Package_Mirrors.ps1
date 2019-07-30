param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SAE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../../dsg_deploy_scripts/DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId)

# Switch to appropriate management subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;

# Read additional parameters that will be passed to the bash script from the config file
$subscription = $config.shm.subscriptionName
$keyvaultName = $config.dsg.mirrors.keyvault.name
$resourceGroupName = $config.dsg.mirrors.rg
$tier = $config.dsg.tier

# Convert arguments into the format expected by mirror deployment scripts
$arguments = "-s '$subscription' \
              -k $keyvaultName \
              -r $resourceGroupName \
              -t $tier"

# Get path to bash scripts
$deployScriptDir = Join-Path (Get-Item $PSScriptRoot).Parent.Parent "azure-vms" -Resolve

# Deploy external mirror servers
Write-Host "Deploying external mirror servers"
$cmd = "$deployScriptDir/deploy_azure_external_mirror_servers.sh $arguments"
bash -c $cmd

# Deploy internal mirror servers
Write-Host "Deploying internal mirror servers"
$cmd = "$deployScriptDir/deploy_azure_internal_mirror_servers.sh $arguments"
bash -c $cmd


# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
