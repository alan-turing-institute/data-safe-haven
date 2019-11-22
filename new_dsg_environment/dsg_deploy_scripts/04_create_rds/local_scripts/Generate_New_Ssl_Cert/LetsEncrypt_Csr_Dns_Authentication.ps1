param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$subscriptionName,
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$hostName,
  [Parameter(Position=3, Mandatory = $true, HelpMessage = "DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dnsResourceGroup
)

Import-Module Az

# Temporarily switch subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $subscriptionName;

$certbotDomain = (Get-ChildItem Env:CERTBOT_DOMAIN).Value
$certbotValidation = (Get-ChildItem Env:CERTBOT_VALIDATION).Value
$dnsRecordname = ("_acme-challenge." + "$hostname".ToLower())
$dnsTtlSeconds = 30

Write-Host " - (Re-)creating Let's Encrypt DNS verification record for SRE $sreId ($certbotDomain)"
Remove-AzDnsRecordSet -Name $dnsRecordname -RecordType TXT -ZoneName $sreDomain -ResourceGroupName $dnsResourceGroup
$_ = New-AzDnsRecordSet -Name $dnsRecordname -RecordType TXT -ZoneName $sreDomain `
                        -ResourceGroupName $dnsResourceGroup -Ttl $dnsTtlSeconds `
                        -DnsRecords (New-AzDnsRecordConfig -Value "$certbotValidation")

# Wait to ensure that any previous lookup of this record has expired
$delaySeconds = $dnsTtlSeconds
Write-Host " - Waiting $delaySeconds seconds to ensure DNS TTL expires"
Start-Sleep -Seconds $delaySeconds

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;

