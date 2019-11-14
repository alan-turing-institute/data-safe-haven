param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Which tier of mirrors should be deployed")]
  [ValidateSet("2", "3")]
  [string]$tier
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force

# Get SHM config
# --------------
$config = Get-ShmFullConfig($shmId)

# Switch to appropriate management subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName;

# Convert arguments into the format expected by mirror deployment scripts
$SHM_ID = "$($config.id)".ToUpper()
$arguments = "-s '$($config.subscriptionName)' \
              -i $SHM_ID \
              -k $($config.keyVault.Name) \
              -r $($config.mirrors.rg) \
              -t $tier \
              -v $($config.network.vnet.rg)"

# Get path to bash scripts
$deployScriptDir = Join-Path (Get-Item $PSScriptRoot).Parent.Parent "new_dsg_environment" "azure-vms" -Resolve

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
