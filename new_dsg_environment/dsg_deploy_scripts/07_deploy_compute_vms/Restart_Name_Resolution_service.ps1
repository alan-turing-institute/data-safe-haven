param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Enter last octet of compute VM IP address (e.g. 160)")]
  [string]$ipLastOctet
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to management subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.dsg.subscriptionName;


# Find VM with private IP address matching the provided last octect
## Turn provided last octect into full IP address in the data subnet
$vmIpAddress = ($config.dsg.network.subnets.data.prefix + "." + $ipLastOctet)
Write-Host " - Finding VM with IP $vmIpAddress"
## Get all compute VMs
$computeVms = Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg
## Get the NICs attached to all the compute VMs
$computeVmNicIds = ($computeVms | ForEach-Object{(Get-AzVM -ResourceGroupName $config.dsg.dsvm.rg -Name $_.Name).NetworkProfile.NetworkInterfaces.Id})
$computeVmNics = ($computeVmNicIds | ForEach-Object{Get-AzNetworkInterface -ResourceGroupName $config.dsg.dsvm.rg -Name $_.Split("/")[-1]})
## Filter the NICs to the one matching the desired IP address and get the name of the VM it is attached to
$computeVmName = ($computeVmNics | Where-Object{$_.IpConfigurations.PrivateIpAddress -match $vmIpAddress})[0].VirtualMachine.Id.Split("/")[-1]

# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "restart_name_resolution_service.sh"
$testHost = ("rdssh1." + $config.dsg.domain.fqdn)
Write-Host " - Restarting name resolution service on VM $computeVmName"
$result = Invoke-AzVMRunCommand -ResourceGroupName $config.dsg.dsvm.rg -Name "$computeVmName" `
    -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter @{"TEST_HOST"="$testHost"};

Write-Output $result.Value;

# Switch back to previous subscription
Set-AzContext -Context $prevContext;
