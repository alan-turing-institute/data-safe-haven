param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter DSG ID (usually a number e.g enter '9' for DSG9)")]
  [string]$dsgId
)

Import-Module Az
Import-Module $PSScriptRoot/../DsgConfig.psm1 -Force

# Get DSG config
$config = Get-DsgConfig($dsgId);

# Temporarily switch to DSG subscription
$prevContext = Get-AzContext
Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# Configure data server
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_Data_Server_Remote.ps1"

$params = @{
  dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
  shmNetbiosName = "`"$($config.shm.domain.netBiosName)`""
  researcherUserSgName = "`"$($config.dsg.domain.securityGroups.researchUsers.name)`""
  serverAdminSgName = "`"$($config.dsg.domain.securityGroups.serverAdmins.name)`""
};
$vmResourceGroup = $config.dsg.dataserver.rg
$vmName = $config.dsg.dataserver.vmName;

Write-Host " - Configuring RDS Servers"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup -Name "$vmName" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params
    
Write-Output $result.Value;

# Switch back to previous subscription
Set-AzContext -Context $prevContext;

