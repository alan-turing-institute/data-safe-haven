# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $dsgFqdn,
  $identitySubnetPrefix,
  $rdsSubnetPrefix,
  $dataSubnetPrefix
)

function IpPrefixToInAddrArpa($ipPrefix)
{
    $octetList = @($ipPrefix.split("."))
    [array]::Reverse($octetList)
    $ipPrefixRev = $octetList -join "."
    return "$ipPrefixRev.in-addr.arpa"
}
function Remove-DsgDnsZone($zoneName) {
  if(Get-DnsServerZone | Where-Object {$_.ZoneName -eq "$zoneName"}){
    Write-Output "Removing '$zoneName' DNS record"
    Remove-DnsServerZone $zoneName -Force 
  } else {
    Write-Output "No '$zoneName' DNS record exists"
  }
}

Remove-DsgDnsZone $dsgFqdn 
Remove-DsgDnsZone (IpPrefixToInAddrArpa $identitySubnetPrefix)
Remove-DsgDnsZone (IpPrefixToInAddrArpa $rdsSubnetInAddrArpa)
Remove-DsgDnsZone (IpPrefixToInAddrArpa $dataSubnetPrefix)
