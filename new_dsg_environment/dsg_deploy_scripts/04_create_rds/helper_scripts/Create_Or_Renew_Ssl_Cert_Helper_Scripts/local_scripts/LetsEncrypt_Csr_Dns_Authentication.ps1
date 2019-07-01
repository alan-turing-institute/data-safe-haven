param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module (Join-Path $PSScriptRoot ".." ".." ".." ".." "DsgConfig.psm1") -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName;

$certbotDomain = (Get-ChildItem Env:CERTBOT_DOMAIN).Value
$certbotValidation = (Get-ChildItem Env:CERTBOT_VALIDATION).Value
$dnsRecordname = ("_acme-challenge." + "$($config.dsg.rds.gateway.hostname)".ToLower())
$dnsTtlSeconds = 30

$dnsResourceGroup = $config.shm.dns.rg
$dsgDomain = $config.dsg.domain.fqdn

Write-Host " - (Re-)creating Let's Encrypt DNS verification record for DSG $dsgId ($certbotDomain)"
Remove-AzDnsRecordSet -Name $dnsRecordname -RecordType TXT -ZoneName $dsgDomain -ResourceGroupName $dnsResourceGroup
$_ = New-AzDnsRecordSet -Name $dnsRecordname -RecordType TXT -ZoneName $dsgDomain `
    -ResourceGroupName $dnsResourceGroup -Ttl $dnsTtlSeconds `
    -DnsRecords (New-AzDnsRecordConfig -Value "$certbotValidation")

# Wait to ensure that any previous lookup of this record has expired
$delaySeconds = $dnsTtlSeconds
Write-Host " - Waiting $delaySeconds seconds to ensure DNS TTL expires"
Start-Sleep -Seconds $delaySeconds

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;

Exit 0
