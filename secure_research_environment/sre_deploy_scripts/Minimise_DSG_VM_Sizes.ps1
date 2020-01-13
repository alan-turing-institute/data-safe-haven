param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force

# Get DSG config
$config = Get-SreConfig($dsgId)

$vmSize = "Standard_B2ms"

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

Write-Host "Resizing all VMs in DSG $($config.dsg.id) to size '$vmSize'"

Write-Host "===Resizing all compute VMs==="
Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg | ForEach-Object {$vm = $_; $vm.HardwareProfile.VmSize = $vmSize; Update-AzVM -VM $vm -ResourceGroupName $config.dsg.dsvm.rg -NoWait}
Write-Host "===Resizing web app servers==="
$vm = Get-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.gitlab.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.dsg.linux.rg -NoWait
$vm = Get-AzVM -ResourceGroupName $config.dsg.linux.rg -Name $config.dsg.linux.hackmd.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.dsg.linux.rg -NoWait
Write-Host "===Resizing dataserver==="
$vm = Get-AzVM -ResourceGroupName $config.dsg.dataserver.rg -Name $config.dsg.dataserver.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.dsg.dataserver.rg -NoWait
Write-Host "===Resizing RDS session hosts==="
$vm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionHost1.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.dsg.rds.rg -NoWait
$vm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.sessionHost2.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.dsg.rds.rg -NoWait
Write-Host "===Resizing RDS gateway==="
$vm = Get-AzVM -ResourceGroupName $config.dsg.rds.rg -Name $config.dsg.rds.gateway.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.dsg.rds.rg -NoWait
Write-Host "===Resizing AD DC==="
$vm = Get-AzVM -ResourceGroupName $config.dsg.dc.rg -Name $config.dsg.dc.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.dsg.dc.rg -NoWait

# Switch back to original subscription
$_ = Set-AzContext -Context $prevContext;
