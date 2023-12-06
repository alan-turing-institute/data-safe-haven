param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. 'project'; maximum of seven alphanumeric characters)")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "Use device authentication for connecting to Azure and Microsoft Graph")]
    [switch]$UseDeviceAuthentication
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Microsoft.Graph.Authentication -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop


# Connect to Azure
# ----------------
if (Get-AzContext) { Disconnect-AzAccount | Out-Null } # force a refresh of the Azure token before starting
Add-LogMessage -Level Info "Attempting to authenticate with Azure. Please sign in with an account with admin rights over the subscriptions you plan to use."
if ($UseDeviceAuthentication) {
    Connect-AzAccount -UseDeviceAuthentication -ErrorAction Stop | Out-Null
} else {
    Connect-AzAccount -ErrorAction Stop | Out-Null
}
if (Get-AzContext) {
    Add-LogMessage -Level Success "Authenticated with Azure as $((Get-AzContext).Account.Id)"
} else {
    Add-LogMessage -Level Fatal "Failed to authenticate with Azure"
}


# Connect to Microsoft Graph
# --------------------------
if (Get-MgContext) { Disconnect-MgGraph | Out-Null } # force a refresh of the Microsoft Graph token before starting
Add-LogMessage -Level Info "Attempting to authenticate with Microsoft Graph. Please sign in with an account with admin rights over the Azure Active Directory you plan to use."
if ($UseDeviceAuthentication) {
    Connect-MgGraph -TenantId $config.azureAdTenantId -Scopes "User.ReadWrite.All", "UserAuthenticationMethod.ReadWrite.All", "Directory.AccessAsUser.All", "RoleManagement.ReadWrite.Directory" -ErrorAction Stop -ContextScope Process -UseDeviceAuthentication
} else {
    Connect-MgGraph -TenantId $config.azureAdTenantId -Scopes "User.ReadWrite.All", "UserAuthenticationMethod.ReadWrite.All", "Directory.AccessAsUser.All", "RoleManagement.ReadWrite.Directory" -ErrorAction Stop -ContextScope Process | Out-Null
}
if (Get-MgContext) {
    Add-LogMessage -Level Success "Authenticated with Microsoft Graph as $((Get-MgContext).Account)"
} else {
    Add-LogMessage -Level Fatal "Failed to authenticate with Microsoft Graph"
}


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -Subscription $config.dns.subscriptionName -ErrorAction Stop


# Check Powershell requirements
# -----------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot '..' '..' 'CheckRequirements.ps1')" }


# Deploy the SHM KeyVault and register emergency user with AAD
# ------------------------------------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SHM_Key_Vault_And_Emergency_Admin.ps1')" -shmId $shmId }


# Setup SHM networking and VPN
# ----------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SHM_Networking.ps1')" -shmId $shmId }


# Setup SHM monitoring
# --------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SHM_Monitoring.ps1')" -shmId $shmId }


# Setup SHM firewall and routing
# ------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SHM_Firewall.ps1')" -shmId $shmId }


# Setup SHM storage accounts
# --------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SHM_Storage_Accounts.ps1')" -shmId $shmId }


# Setup SHM domain controllers
# ----------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SHM_DC.ps1')" -shmId $shmId }


# Setup SHM update servers
# ------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SHM_Update_Servers.ps1')" -shmId $shmId }


# Setup SHM package repositories
# ------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SHM_Package_Repositories.ps1')" -shmId $shmId }


# Register all SHM VMs with LogAnalytics
# --------------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SHM_Register_VMs.ps1')" -shmId $shmId }


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
