# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in 
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# Fror details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
  $rdsGatewayIp,
  $rdsGatewayFqdn,
  $npsSecret,
  $dsgId
)

if(Get-NpsRadiusClient | Where-Object {$_.Name -eq "$rdsGatewayFqdn"}){
  Write-Output "   - RADIUS Client '$rdsGatewayFqdn' already exists"
} else {
  Write-Output "   - Creating RADIUS client '$rdsGatewayFqdn' at '$rdsGatewayIp'"
  $_ = New-NpsRadiusClient -Address $rdsGatewayIp -Name "$rdsGatewayFqdn" -SharedSecret "$npsSecret"
}

$ruleName = "DSGROUP$dsgId RDS Gateway RADIUS inbound ($rdsGatewayIp)"
if(Get-NetFirewallRule | Where-Object {$_.DisplayName -eq "$ruleName"}){
  Write-Output "   - Inbound RADIUS firewall rule '$ruleName' already exists"
} else {
  Write-Output "   - Adding '$ruleName' inbound RADIUS firewall rule for $rdsGatewayFqdn ($rdsGatewayIp)"
  $_ = New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -RemoteAddress $rdsGatewayIp -Action Allow -Protocol UDP -LocalPort "1812","1813" -Profile Domain -Enabled True
}
