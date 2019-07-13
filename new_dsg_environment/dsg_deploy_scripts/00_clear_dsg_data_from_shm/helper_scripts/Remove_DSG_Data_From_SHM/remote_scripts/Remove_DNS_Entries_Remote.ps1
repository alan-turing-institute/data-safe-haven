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


Write-Output "Removing DNS record for DSG domain ($dsgFqdn)"
Remove-DnsServerZone $dsgFqdn -Force -PassThru -Verbose 

$identitySubnetInAddrArpa = IpPrefixToInAddrArpa $identitySubnetPrefix
Write-Output "Removing DNS record for Identity subnet ($identitySubnetInAddrArpa)" 
Remove-DnsServerZone $identitySubnetInAddrArpa -Force -PassThru -Verbose

$rdsSubnetInAddrArpa = IpPrefixToInAddrArpa $rdsSubnetPrefix
Write-Output "Removing DNS record for RDS subnet ($rdsSubnetInAddrArpa)" 
Remove-DnsServerZone $rdsSubnetInAddrArpa -Force -PassThru -Verbose

$dataSubnetInAddrArpa = IpPrefixToInAddrArpa $dataSubnetPrefix
Write-Output "Removing DNS record for Data subnet ($dataSubnetInAddrArpa)" 
Remove-DnsServerZone $dataSubnetInAddrArpa -Force -PassThru -Verbose
