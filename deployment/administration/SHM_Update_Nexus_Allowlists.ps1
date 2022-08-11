param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "Path to directory containing allowlist files (default: '<repo root>/environment_configs/package_lists')")]
    [string]$allowlistDirectory = $null
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module $PSScriptRoot/../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Common variable names
# ---------------------
$tier = "3"  # currently only Tier-3 enforces allowlists
if (-not $allowlistDirectory) { $allowlistDirectory = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" }


# Construct script to
#
# 1. Write PyPI allowlist
# 2. Write CRAN allowlist
# 3. Run nexus update job
$script = "#! /bin/sh`n"

foreach ($proxy in @("pypi", "cran")) {
    # Read proxy allowlist
    $allowlistPath = Join-Path $allowlistDirectory "allowlist-full-${fullMirrorType}-tier${tier}.list".ToLower() -Resolve
    Add-LogMessage -Level Info "Using allowlist from '$allowlistPath'"

    $allowList = Get-Content $allowlistPath -Raw -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Failure "Could not find allowlist at '$allowlistPath'"
    }

    # Empty existing allowlist
    $script += "cat /dev/null > /etc/nexus/allowlist-${proxy}`n"

    # Write items from local allowlist to remote
    $script += "cat << EOF > /etc/nexus/allowlist-${proxy}`n"
    foreach ($package in $allowList -split "`n") {
        $script += "${package}`n"
    }
    $script += "EOF`n"
}

# Run nexus update script
$script += "/usr/local/update-nexus-allowlists"

# Ensure Nexus VM is running
$vmName = $config.repository["tier${tier}"].nexus.vmName
$vmStatus = Get-VMState -ResourceGroupName $config.repository.rg -Name $vmName
if ($vmStatus -eq "VM does not exist") {
    Add-LogMessage -Level Failure "VM '$vmName' does not exist. Have you deployed a Nexus VM?"
} elseif ($vmStatus -ne "VM running") {
    Add-LogMessage -Level Failure "VM '$vmName' is not running. Current status: '$vmStatus'."
}

# Run the script on the Nexus VM
Add-LogMessage -Level Info "Updating allowlists on $vmName"
$null = Invoke-RemoteScript -VMName $vmName -ResourceGroupName $config.repository.rg -Shell "UnixShell" -Script $script


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
