param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Path to SSL certificate signed by Certificate Authority (in .pem ASCII format, inclding CA cert chain)")]
  [string]$certFullChainPath,
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "Remote folder to write SSL certificate to")]
  [string]$remoteDirectory
)

Import-Module Az
Import-Module (Join-Path $PSScriptRoot ".." ".." ".." ".." "DsgConfig.psm1") -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Find RDS Gateway VM name by IP address
$vmResourceGroup = $config.dsg.rds.rg;
$vmIpAddress = $config.dsg.rds.gateway.ip
Write-Host " - Finding VM with IP $vmIpAddress"
## Get all VMs in resource group
$vms = Get-AzVM -ResourceGroupName $vmResourceGroup
## Get the NICs attached to all the VMs in the resource group
$vmNicIds = ($vms | ForEach-Object{(Get-AzVM -ResourceGroupName $vmResourceGroup -Name $_.Name).NetworkProfile.NetworkInterfaces.Id})
$vmNics = ($vmNicIds | ForEach-Object{Get-AzNetworkInterface -ResourceGroupName $vmResourceGroup -Name $_.Split("/")[-1]})
## Filter the NICs to the one matching the desired IP address and get the name of the VM it is attached to
$vmName = ($vmNics | Where-Object{$_.IpConfigurations.PrivateIpAddress -match $vmIpAddress})[0].VirtualMachine.Id.Split("/")[-1]
Write-Host " - VM '$vmName' found"

# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote_scripts" "Install_Signed_Ssl_Cert_Remote.ps1"

$certFilename = (Split-Path -Leaf -Path $certFullChainPath)
$certFullChain = (@(Get-Content -Path $certFullChainPath) -join "|")

$params = @{
    certFullChain = "`"$certFullChain`""
    certFilename = "`"$certFilename`""
    remoteDirectory = "`"$remoteDirectory`""
    rdsFqdn = "`"$($config.dsg.rds.gateway.fqdn)`""
};

Write-Host " - Installing SSL certificate on VM '$vmName'"

Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup -Name $vmName `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params
    
# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;