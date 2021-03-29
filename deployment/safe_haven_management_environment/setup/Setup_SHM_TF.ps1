param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop

# Setup terraform resource group 
# ------------------------------------------------------------
$null = Deploy-ResourceGroup -Name $config.terraform.rg -Location $config.location

# Setup terraform storage account
# ------------------------------------------------------------
$storageAccount = Deploy-StorageAccount -Name $config.terraform.accountName -ResourceGroupName $config.terraform.rg -Location $config.location

# Create blob storage container
# ------------------------------------------------------------
Add-LogMessage -Level Info "Ensuring that terraform blob storage container exists..."
$null = Deploy-StorageContainer -Name $config.terraform.containerName -StorageAccount $storageAccount
