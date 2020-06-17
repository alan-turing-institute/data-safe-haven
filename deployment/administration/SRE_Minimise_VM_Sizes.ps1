param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Resize all VMs
# --------------
$vmSize = "Standard_B2ms"
Add-LogMessage -Level Info "Resizing all VMs in SRE $($config.sre.id) to size '$vmSize'"
Add-LogMessage -Level Info "Resizing all compute VMs..."
Get-AzVM -ResourceGroupName $config.sre.dsvm.rg | ForEach-Object {$vm = $_; $vm.HardwareProfile.VmSize = $vmSize; Update-AzVM -VM $vm -ResourceGroupName $config.sre.dsvm.rg -NoWait}
Add-LogMessage -Level Info "Resizing web app servers..."
$vm = Get-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.gitlab.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.sre.webapps.rg -NoWait
$vm = Get-AzVM -ResourceGroupName $config.sre.webapps.rg -Name $config.sre.webapps.hackmd.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.sre.webapps.rg -NoWait
Add-LogMessage -Level Info "Resizing dataserver..."
$vm = Get-AzVM -ResourceGroupName $config.sre.dataserver.rg -Name $config.sre.dataserver.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.sre.dataserver.rg -NoWait
Add-LogMessage -Level Info "Resizing RDS session hosts..."
$vm = Get-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost1.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.sre.rds.rg -NoWait
$vm = Get-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.sessionHost2.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.sre.rds.rg -NoWait
Add-LogMessage -Level Info "Resizing RDS gateway..."
$vm = Get-AzVM -ResourceGroupName $config.sre.rds.rg -Name $config.sre.rds.gateway.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.sre.rds.rg -NoWait
Add-LogMessage -Level Info "Resizing AD DC..."
$vm = Get-AzVM -ResourceGroupName $config.sre.dc.rg -Name $config.sre.dc.vmName
$vm.HardwareProfile.VmSize = $vmSize
Update-AzVM -VM $vm -ResourceGroupName $config.sre.dc.rg -NoWait


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
