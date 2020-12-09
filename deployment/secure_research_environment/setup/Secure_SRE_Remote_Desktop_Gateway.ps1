param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Mandatory = $false, HelpMessage = "Email address to associate with the certificate request.")]
    [string]$emailAddress = "dsgbuild@turing.ac.uk",
    [Parameter(Mandatory = $false, HelpMessage = "Do a 'dry run' against the Let's Encrypt staging server.")]
    [switch]$dryRun,
    [Parameter(Mandatory = $false, HelpMessage = "Force the installation step even for dry runs.")]
    [switch]$forceInstall
)

Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Disable legacy TLS on the RDS gateway
# -------------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Disable_Legacy_TLS.ps1')" -configId $configId }


# Configure CAP and RAP settings on the RDS gateway
# -------------------------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Configure_SRE_RDS_CAP_And_RAP.ps1')" -configId $configId }


# Update the SSL certificates on the RDS gateway
# ----------------------------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Update_SRE_RDS_SSL_Certificate.ps1')" -configId $configId -emailAddress $emailAddress -dryRun:$dryRun -forceInstall:$forceInstall }


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
