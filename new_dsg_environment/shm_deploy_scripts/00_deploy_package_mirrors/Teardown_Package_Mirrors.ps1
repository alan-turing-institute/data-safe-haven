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
Set-AzContext -SubscriptionId $config.shm.subscriptionName;

# Read additional parameters that will be passed to the bash script from the config file
$subscription = $config.shm.subscriptionName
$resourceGroupName = $config.dsg.mirrors.rg
$tier = $config.dsg.tier

# Convert arguments into the format expected by mirror deployment scripts
$arguments = "-s '$subscription' \
              -r $resourceGroupName \
              -t $tier"

# Get path to bash scripts
$deployScriptDir = Join-Path (Get-Item $PSScriptRoot).Parent.Parent "azure-vms" -Resolve

# Teardown PyPI mirror servers
Write-Host "Tearing down PyPI mirror servers"
$cmd = "$deployScriptDir/teardown_azure_mirror_server_set.sh $arguments -m PyPI"
bash -c $cmd

# Teardown CRAN mirror servers
Write-Host "Tearing down CRAN mirror servers"
$cmd = "$deployScriptDir/teardown_azure_mirror_server_set.sh $arguments -m CRAN"
bash -c $cmd

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;