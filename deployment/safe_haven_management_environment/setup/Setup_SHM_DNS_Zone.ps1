param(
  [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$_ = Set-AzContext -Subscription $config.dns.subscriptionName


# Ensure that DNS resource group exists
# -------------------------------------
$_ = Deploy-ResourceGroup -Name $config.dns.rg -Location $config.location


# Create the DNS Zone and set the parent NS records if required
# -------------------------------------------------------------
Set-DnsZoneAndParentNSRecords -DnsZoneName $config.domain.fqdn -ResourceGroupName $config.dns.rg


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
