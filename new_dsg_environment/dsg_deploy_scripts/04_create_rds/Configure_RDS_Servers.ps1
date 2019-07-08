param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$($config.dsg.domain.netbiosName)Id
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($($config.dsg.domain.netbiosName)Id)

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Do OS Prep on all RDS VMs
$scriptPath = Join-Path $PSScriptRoot "Configure_RDS_Servers" "remote_scripts" "OS_Prep.ps1"

$osPrepParams = @{
    dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
    shmFqdn = "`"$($config.shm.domain.fqdn))`""
};

Write-Host " - Running OS Prep on RDS Gateway"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup `
    -Name "$($config.dsg.rds.gateway.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $osPrepParams

Write-Host " - Running OS Prep on RDS Session Host 2"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup `
    -Name "$($config.dsg.rds.sessionHost1.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $osPrepParams

Write-Host " - Running OS Prep on RDS Session Host 2"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup `
    -Name "$($config.dsg.rds.sessionHost2.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $osPrepParams

# Configure RDS servers
$scriptPath = Join-Path $PSScriptRoot "Configure_RDS_Servers" "remote_scripts" "Configure_RDS_Servers_Remote.ps1"

$configureRdsParams = @{
  dsgFqdn = "`"$($config.dsg.domain.fqdn)`""
  dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
  shmNetbiosName = "`"$($config.shm.domain.netBiosName))`""
  dataSubnetIpPrefix = "`"$($config.dsg.network.subnets.data.prefix))`""
};

Write-Host " - Configuring RDS Servers"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup `
    -Name "$($config.dsg.rds.gateway.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $configureRdsParams

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
