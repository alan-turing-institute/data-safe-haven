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





# Configure CAP and RAP settings
# ------------------------------
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "create_rds" "scripts" "Configure_CAP_And_RAP_Remote.ps1"
Add-LogMessage -Level Info "[ ] Configuring CAP and RAP settings on RDS Gateway"
$params = @{
    sreResearchUserSecurityGroup = "`"$($config.sre.domain.securityGroups.researchUsers.name)`""
    shmNetbiosName = "$($config.shm.domain.netbiosName)"
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.rds.gateway.vmName -ResourceGroupName $config.sre.rds.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext;