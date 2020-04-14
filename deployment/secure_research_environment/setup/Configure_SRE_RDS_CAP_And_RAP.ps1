param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName

$npsSecret = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.npsSecret -DefaultLength 12


# Configure CAP and RAP settings
# ------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Configure_CAP_And_RAP_Remote.ps1"
Add-LogMessage -Level Info "[ ] Configuring CAP and RAP settings on RDS Gateway"
$params = @{
    sreResearchUserSecurityGroup = "`"$($config.sre.domain.securityGroups.researchUsers.name)`""
    shmNetbiosName = "$($config.shm.domain.netbiosName)"
    shmNpsIp = "$($config.shm.nps.ip)"
    remoteNpsPriority = 1
    remoteNpsTimeout = 60
    remoteNpsBlackout = 60
    remoteNpsSecret = "$npsSecret"
    remoteNpsRequireAuthAttrib = "Yes"
    remoteNpsAcctSharedSecret = "$npsSecret"
    remoteNpsServerGroup = "`"TS GATEWAY SERVER GROUP`"" # "TS GATEWAY SERVER GROUP" is the group name created when manually configuring an RDS Gateway to use a remote NPS server
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value


# Configure SHM NPS for SRE RDS RADIUS client
# -------------------------------------------
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "Adding RDS Gateway as RADIUS client on SHM NPS"
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Add_RDS_Gateway_RADIUS_Client_Remote.ps1"
$params = @{
    rdsGatewayIp = "`"$($config.sre.rds.gateway.ip)`""
    rdsGatewayFqdn = "`"$($config.sre.rds.gateway.fqdn)`""
    npsSecret = "$npsSecret"
    sreId = "`"$($config.sre.id)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg -Parameter $params
Write-Output $result.Value
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Restart SHM NPS server
# ----------------------
# We restart the SHM NPS server because we get login failures with an "Event 13" error -
# "A RADIUS message was received from the invalid RADIUS client IP address 10.150.9.250"
# The two reliable ways we have found to fix this are:
# 1. Log into the SHM NPS and reset the RADIUS shared secret via the GUI
# 2. Restart the NPS server
# We can only do (2) in a script, so that is what we do. An NPS restart is quite quick.


$prevContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.shm.subscriptionName
Add-LogMessage -Level Info "Restarting NPS Server..."
Enable-AzVM -Name $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg
$_ = Set-AzContext -Context $prevContext

# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;