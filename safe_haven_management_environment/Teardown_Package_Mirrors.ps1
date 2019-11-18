param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Which tier of mirrors should be torn down")]
  [ValidateSet("2", "3")]
  [string]$tier
)

Import-Module Az
Import-Module $PSScriptRoot/../common_powershell/Configuration.psm1 -Force

# # Get DSG config
# $config = Get-DsgConfig($dsgId)
# Get SHM config
# --------------
$config = Get-ShmFullConfig($shmId)

# Switch to appropriate management subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.subscriptionName;

# Convert arguments into the format expected by mirror deployment scripts
$arguments = "-s '$($config.subscriptionName)' \
              -r $($config.mirrors.rg) \
              -t $tier"

# Get path to bash scripts
$deployScriptDir = Join-Path (Get-Item $PSScriptRoot).Parent "new_dsg_environment" "azure-vms" -Resolve

# Teardown PyPI mirror servers
Write-Host "Tearing down PyPI mirror servers"
$cmd = "$deployScriptDir/teardown_azure_mirror_server_set.sh $arguments -m PYPI"
bash -c $cmd

# Teardown CRAN mirror servers
Write-Host "Tearing down CRAN mirror servers"
$cmd = "$deployScriptDir/teardown_azure_mirror_server_set.sh $arguments -m CRAN"
bash -c $cmd

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;