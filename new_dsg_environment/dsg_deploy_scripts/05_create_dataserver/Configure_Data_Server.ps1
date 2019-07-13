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
$_ = Set-AzContext -SubscriptionId $config.dsg.subscriptionName;

# === Move Data Server VM into correct OUs ===
$helperScriptDir = Join-Path $PSScriptRoot "helper_scripts" "Configure_Data_Server";
$vmOuMoveParams = @{
    dsgDn = "`"$($config.dsg.domain.dn)`""
    dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
    dataServerHostname = "`"$($config.dsg.dataserver.hostname)`""
};
$scriptPath = Join-Path $helperScriptDir "remote_scripts" "Move_Data_Server_VM_Into_OU.ps1"
Write-Host " - Moving Data Server VM to correct OU on DSG DC"
Invoke-AzVMRunCommand -ResourceGroupName $($config.dsg.dc.rg) `
    -Name "$($config.dsg.dc.vmName)" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $vmOuMoveParams

# === Configure data server ===
$scriptPath = Join-Path $helperScriptDir  "remote_scripts" "Configure_Data_Server_Remote.ps1"

$params = @{
  dsgNetbiosName = "`"$($config.dsg.domain.netbiosName)`""
  shmNetbiosName = "`"$($config.shm.domain.netbiosName)`""
  researcherUserSgName = "`"$($config.dsg.domain.securityGroups.researchUsers.name)`""
  serverAdminSgName = "`"$($config.dsg.domain.securityGroups.serverAdmins.name)`""
};
$vmResourceGroup = $config.dsg.dataserver.rg
$vmName = $config.dsg.dataserver.vmName;

Write-Host " - Configuring Data Server"
Invoke-AzVMRunCommand -ResourceGroupName $vmResourceGroup -Name "$vmName" `
    -CommandId 'RunPowerShellScript' -ScriptPath $scriptPath `
    -Parameter $params

# Switch back to previous subscription
$_ = Set-AzContext -Context $prevContext;

