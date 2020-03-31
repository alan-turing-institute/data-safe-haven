param(
  [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId,
  [Parameter(Position = 1, Mandatory = $false, HelpMessage = "Do not set NS records in parent DNS Zone")]
  [switch]$DoNotSetParentNs = $false
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext


# Set to Domains subscription
# ---------------------------
$_ = Set-AzContext -Subscription $config.dns.subscriptionName


# Create the DNS Zone and set the parent NS records if required
# -------------------------------------------------------------
Set-DnsZoneAndParentNSRecordss -DnsZoneName $config.domain.fqdn -ResourceGroupName $config.dns.rg -DoNotSetParentNs:$DoNotSetParentNs


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
