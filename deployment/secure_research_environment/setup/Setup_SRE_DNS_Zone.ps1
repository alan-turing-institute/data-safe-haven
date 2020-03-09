param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId,
  [Parameter(Position = 1, Mandatory = $false, HelpMessage = "Do not set NS records in parent DNS Zone")]
  [switch]$DoNotSetParentNs = $false
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext


# Set to Domains subscription
# ---------------------------
$_ = Set-AzContext -Subscription $config.shm.dns.subscriptionName


# Create the DNS Zone and set the parent NS records if required
# -------------------------------------------------------------
CreateDnsZoneAndSetParentNSRecords -DnsZoneName $config.sre.domain.fqdn -ResourceGroupName $config.shm.dns.rg -DoNotSetParentNs:$DoNotSetParentNs


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
