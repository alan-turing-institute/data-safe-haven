param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureAutomation -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Create resource groups if they do not exist
# -------------------------------------------
$null = Deploy-ResourceGroup -Name $config.logging.rg -Location $config.location
$null = Deploy-ResourceGroup -Name $config.automation.rg -Location $config.location


# Deploy Log Analytics workspace
# ------------------------------
$workspace = Deploy-LogAnalyticsWorkspace -Name $config.logging.workspaceName -ResourceGroupName $config.logging.rg -Location $config.location


# Deploy automation account
# -------------------------
$account = Deploy-AutomationAccount -Name $config.automation.accountName -ResourceGroupName $config.automation.rg -Location $config.location
$null = Connect-AutomationAccountLogAnalytics -AutomationAccountName $account.AutomationAccountName -LogAnalyticsWorkspace $workspace
$null = Deploy-LogAnalyticsSolution -Workspace $workspace -SolutionType "Updates"


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
