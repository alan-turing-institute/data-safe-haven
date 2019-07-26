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

# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote_scripts" "Install_Signed_Ssl_Cert_Remote.ps1"
$vmResourceGroup = $config.dsg.rds.rg
$vmName = $config.dsg.rds.gateway.vmName
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