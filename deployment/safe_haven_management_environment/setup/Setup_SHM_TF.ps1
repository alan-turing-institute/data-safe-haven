param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

# Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$az_context = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop

# # Setup terraform resource group 
# # ------------------------------------------------------------
# $null = Deploy-ResourceGroup -Name $config.terraform.rg -Location $config.location

# # Setup terraform storage account
# # ------------------------------------------------------------
# $storageAccount = Deploy-StorageAccount -Name $config.terraform.accountName -ResourceGroupName $config.terraform.rg -Location $config.location

# # Create blob storage container
# # ------------------------------------------------------------
# $null = Deploy-StorageContainer -Name $config.terraform.containerName -StorageAccount $storageAccount

# Prepare main.tf file
# ------------------------------------------------------------
$main_file = '../terraform/main.tf'
Copy-Item ../terraform/main.tf_template $main_file
(Get-Content $main_file).replace('<<<subscription_id>>>', $az_context.Subscription.Id) | Set-Content $main_file
(Get-Content $main_file).replace('<<<resource_group_name>>>', $config.terraform.rg) | Set-Content $main_file
(Get-Content $main_file).replace('<<<storage_account_name>>>', $config.terraform.accountName) | Set-Content $main_file
(Get-Content $main_file).replace('<<<container_name>>>', $config.terraform.containerName) | Set-Content $main_file
(Get-Content $main_file).replace('<<<key>>>', $config.terraform.keyName) | Set-Content $main_file

# Prepare terraform.tfvars file
# ------------------------------------------------------------
$tfvars_file = '../terraform/terraform.tfvars'
Copy-Item ../terraform/terraform.tfvars_template $tfvars_file

# DNS
# (Get-Content $tfvars_file).replace('<<<dns_rg_name>>>', $config.dns.rg) | Set-Content $tfvars_file
# (Get-Content $tfvars_file).replace('<<<dns_rg_location>>>', $config.location) | Set-Content $tfvars_file

# Key Vault
(Get-Content $tfvars_file).replace('<<<kv_rg_name>>>', $config.keyVault.rg) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_rg_location>>>', $config.location) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_name>>>', $config.keyVault.name) | Set-Content $tfvars_file
(Get-Content $tfvars_file).replace('<<<kv_location>>>', $config.location) | Set-Content $tfvars_file

$kvSecurityGroupId = (Get-AzADGroup -DisplayName $config.azureAdminGroupName)[0].Id
(Get-Content $tfvars_file).replace('<<<kv_security_group_id>>>', $kvSecurityGroupId) | Set-Content $tfvars_file

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop