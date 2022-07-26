param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Check that we are using the correct provider
# --------------------------------------------
if ($config.sre.remoteDesktop.provider -ne "MicrosoftRDS") {
    Add-LogMessage -Level Fatal "You should not be running this script when using remote desktop provider '$($config.sre.remoteDesktop.provider)'"
}


# Configure CAP and RAP settings
# ------------------------------
Add-LogMessage -Level Info "Creating/retrieving NPS secret from Key Vault '$($config.sre.keyVault.name)'..."
$npsSecret = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.npsSecret -DefaultLength 12 -AsPlaintext


# Configure CAP and RAP settings
# ------------------------------
Add-LogMessage -Level Info "[ ] Configuring CAP and RAP settings on RDS Gateway"
$params = @{
    npsSecretB64                 = $npsSecret | ConvertTo-Base64
    remoteNpsBlackout            = "60"
    remoteNpsPriority            = "1"
    remoteNpsRequireAuthAttrib   = "Yes"
    remoteNpsServerGroup         = "TS GATEWAY SERVER GROUP" # "TS GATEWAY SERVER GROUP" is the group name created when manually configuring an RDS Gateway to use a remote NPS server
    remoteNpsTimeout             = "60"
    shmNetbiosName               = $config.shm.domain.netbiosName
    shmNpsIp                     = $config.shm.nps.ip
    sreResearchUserSecurityGroup = $config.sre.domain.securityGroups.researchUsers.name
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Configure_CAP_And_RAP_Remote.ps1"
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.remoteDesktop.gateway.vmName -ResourceGroupName $config.sre.remoteDesktop.rg -Parameter $params


# Configure SHM NPS for SRE RDS RADIUS client
# -------------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
Add-LogMessage -Level Info "Adding RDS Gateway as RADIUS client on SHM NPS"
# Run remote script
$params = @{
    npsSecretB64   = $npsSecret | ConvertTo-Base64
    rdsGatewayIp   = $config.sre.remoteDesktop.gateway.ip
    rdsGatewayFqdn = $config.sre.remoteDesktop.gateway.fqdn
    sreId          = $config.sre.id
}
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Add_RDS_Gateway_RADIUS_Client_Remote.ps1"
$null = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg -Parameter $params
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Restart SHM NPS server
# ----------------------
# We restart the SHM NPS server because we get login failures with an "Event 13" error -
# "A RADIUS message was received from the invalid RADIUS client IP address 10.150.9.250"
# The two reliable ways we have found to fix this are:
# 1. Log into the SHM NPS and reset the RADIUS shared secret via the GUI
# 2. Restart the NPS server
# We can only do (2) in a script, so that is what we do. An NPS restart is quite quick.
# -------------------------------------------------------------------------------------
$null = Set-AzContext -SubscriptionId $config.shm.subscriptionName -ErrorAction Stop
Add-LogMessage -Level Info "Restarting NPS Server..."
# Restart SHM NPS
Start-VM -Name $config.shm.nps.vmName -ResourceGroupName $config.shm.nps.rg -ForceRestart
# Wait 2 minutes for NPS to complete post-restart boot and start NPS services
Add-LogMessage -Level Info "Waiting 2 minutes for NPS services to start..."
Start-Sleep 120
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
