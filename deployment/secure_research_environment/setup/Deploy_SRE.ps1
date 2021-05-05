param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $true, HelpMessage = "Azure Active Directory tenant ID")]
    [string]$tenantId,
    [Parameter(Mandatory = $true, HelpMessage = "Array of sizes of DSVMs to deploy. For example: 'Standard_D2s_v3', 'default', 'Standard_NC6s_v3'")]
    [string[]]$VmSizes,
    [Parameter(Mandatory = $false, HelpMessage = "Remove any remnants of previous deployments of this SRE from the SHM")]
    [switch]$Clean
)

Import-Module Az.Accounts
if (-not (Get-Module -Name "Microsoft.Graph.Authentication")) { Import-Module Microsoft.Graph.Authentication -ErrorAction Stop }
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Sto


# Connect to Azure
# ----------------
if (Get-AzContext) { Disconnect-AzAccount } # force a refresh of the Azure token before starting
Add-LogMessage -Level Info "Attempting to authenticate with Azure"
Connect-AzAccount -ErrorAction Stop
if (Get-AzContext) {
    Add-LogMessage -Level Success "Authenticated with Azure"
} else {
    Add-LogMessage -Level Fatal "Failed to authenticate with Azure"
}


# Connect to Microsoft Graph
# --------------------------
if (Get-MgContext) { Disconnect-MgGraph } # force a refresh of the Microsoft Graph token before starting
Add-LogMessage -Level Info "Attempting to authenticate with Microsoft Graph"
Connect-MgGraph -TenantId $tenantId -Scopes "Application.ReadWrite.All","Policy.ReadWrite.ApplicationConfiguration" -ErrorAction Stop
if (Get-MgContext) {
    Add-LogMessage -Level Success "Authenticated with Microsoft Graph"
} else {
    Add-LogMessage -Level Fatal "Failed to authenticate with Microsoft Graph"
}


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Check that we are using the correct provider
# --------------------------------------------
if ($config.sre.remoteDesktop.provider -ne "ApacheGuacamole") {
    Add-LogMessage -Level Fatal "You should not be running this script when using remote desktop provider '$($config.sre.remoteDesktop.provider)'"
}


# Check Powershell requirements
# -----------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot '..' '..' 'CheckRequirements.ps1')" }


# Remove data from previous deployments
# -------------------------------------
if ($Clean) {
    Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Remove_SRE_Data_From_SHM.ps1')" -shmId $shmId -sreId $sreId }
}


# Register SRE with the SHM
# -------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SRE_Key_Vault_And_Users.ps1')" -shmId $shmId -sreId $sreId }


# Create SRE DNS Zone
# -------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SRE_DNS_Zone.ps1')" -shmId $shmId -sreId $sreId }


# Deploy the virtual network
# --------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SRE_Networking.ps1')" -shmId $shmId -sreId $sreId }


# Deploy storage accounts
# -----------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SRE_Storage_Accounts.ps1')" -shmId $shmId -sreId $sreId }


# Deploy Guacamole remote desktop
# -------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SRE_Guacamole_Servers.ps1')" -shmId $shmId -sreId $sreId -tenantId $tenantId }


# Update SSL certificate
# ----------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Update_SRE_SSL_Certificate.ps1')" -shmId $shmId -sreId $sreId }


# Deploy web applications (GitLab and CodiMD)
# -------------------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SRE_WebApp_Servers.ps1')" -shmId $shmId -sreId $sreId }


# Deploy databases
# ----------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SRE_Databases.ps1')" -shmId $shmId -sreId $sreId }


# Deploy data science VMs
# -----------------------
$cpuIpOffset = 160
$gpuIpOffset = 180
foreach ($VmSize in $VmSizes) {
    if ($VmSize.Replace("Standard_", "").StartsWith("N")) {
        Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Add_DSVM.ps1')" -shmId $shmId -sreId $sreId -ipLastOctet $gpuIpOffset -vmSize $VmSize }
        $gpuIpOffset += 1
    } else {
        Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Add_DSVM.ps1')" -shmId $shmId -sreId $sreId -ipLastOctet $cpuIpOffset -vmSize $VmSize }
        $cpuIpOffset += 1
    }
}

# Configure network lockdown
# --------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Apply_SRE_Network_Configuration.ps1')" -shmId $shmId -sreId $sreId }


# Configure firewall
# ------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SRE_Firewall.ps1')" -shmId $shmId -sreId $sreId }


# Configure logging
# ------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Setup_SRE_Logging.ps1')" -shmId $shmId -sreId $sreId }


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
