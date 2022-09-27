param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "Path to directory containing allowlist files (default: '<repo root>/environment_configs/package_lists')")]
    [string]$AllowlistDirectory = $null
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
if (-not $AllowlistDirectory) { $AllowlistDirectory = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" }
$SourceRepositoryNames = @("pypi", "cran")
$tier = "3"  # currently only Tier-3 mirrors have allowlists
$AllowList = @{}


# Load package lists into arrays
# ------------------------------
foreach ($SourceRepositoryName in $SourceRepositoryNames) {
    try {
        $AllowListRepositoryName = "$SourceRepositoryName".ToLower().Replace("cran", "r-cran").Replace("pypi", "python-pypi")
        $AllowListPath = Join-Path $AllowlistDirectory "allowlist-full-${AllowListRepositoryName}-tier${tier}.list".ToLower() -Resolve -ErrorAction Stop
        $AllowList[$SourceRepositoryName] = (Get-Content $AllowListPath -Raw -ErrorAction Stop) -split "`n" | Where-Object { $_ -and (-not $_.StartsWith("#")) } # remove empty lines and commented packages
        Add-LogMessage -Level Info "Loaded allowlist from '$AllowListPath'"
    } catch {
        $AllowList[$SourceRepositoryName] = @()
        Add-LogMessage -Level Error "Could not find allowlist at '$AllowListPath'"
    }
}


# If we are using proxies then construct script to
#
# 1. Write PyPI allowlist
# 2. Write CRAN allowlist
# 3. Run single job to update all Nexus repositories
if ($config.repositories["tier${tier}"].proxies) {
    # Construct single update script
    $script = "#! /bin/bash`n"
    foreach ($SourceRepositoryName in $SourceRepositoryNames) {
        # Empty existing allowlist
        $script += ": > /etc/nexus/allowlist-${SourceRepositoryName}`n" # ':' is the shell no-op command
        # Write items from local allowlist to remote
        $script += "cat << EOF > /etc/nexus/allowlist-${SourceRepositoryName}`n"
        foreach ($package in $AllowList[$SourceRepositoryName]) {
            $script += "${package}`n"
        }
        $script += "EOF`n"
        $script += "echo `"There are `$(wc -l /etc/nexus/allowlist-${SourceRepositoryName} | cut -d' ' -f1)`" packages on the ${SourceRepositoryName} allowlist`n"
    }
    $script += "/usr/local/update-nexus-allowlists`n"
    # Update the allowlists on the proxy VM
    try {
        $vmName = $config.repositories["tier${tier}"].proxies.many.vmName
        Add-LogMessage -Level Info "Updating allowlists on $vmName..."
        # Ensure the VM is running
        $null = Start-VM -Name $vmName -ResourceGroupName $config.repositories.rg
        # Run the script on the Nexus VM
        $null = Invoke-RemoteScript -VMName $vmName -ResourceGroupName $config.repositories.rg -Shell "UnixShell" -Script $script
    } catch {
        Add-LogMessage -Level Error "Could not update allowlists for VM '$vmName'. Is it deployed and running?"
    }
}

# If we are using mirrors then construct one script for each repository type to
#
# 1. Write <respository> allowlist
# 2. Run job to update <respository> mirror
if ($config.repositories["tier${tier}"].mirrorsExternal) {
    foreach ($SourceRepositoryName in $SourceRepositoryNames) {
        # Construct repository update script
        $script = "#! /bin/bash`n"
        # Empty existing allowlist
        $script += ": > /home/mirrordaemon/package_allowlist.txt`n"  # ':' is the shell no-op command
        # Write items from local allowlist to remote
        $script += "cat << EOF > /home/mirrordaemon/package_allowlist.txt`n"
        foreach ($package in $AllowList[$SourceRepositoryName]) {
            $script += "${package}`n"
        }
        $script += "EOF`n"
        $script += "echo `"There are `$(wc -l /home/mirrordaemon/package_allowlist.txt | cut -d' ' -f1)`" packages on the allowlist`n"
        # PyPI also needs us to run the script which updates /etc/bandersnatch.conf
        if ($SourceRepositoryName.ToLower() -eq "pypi") {
            $script += "python3 /home/mirrordaemon/update_bandersnatch_config.py`n"
        }
        # Update the allowlists on the mirror VM
        try {
            $vmName = $config.repositories["tier${tier}"].mirrorsExternal[$SourceRepositoryName].vmName
            Add-LogMessage -Level Info "Updating allowlists on $vmName..."
            # Ensure the VM is running
            $null = Start-VM -Name $vmName -ResourceGroupName $config.repositories.rg
            # Run the script on the mirror VM
            $null = Invoke-RemoteScript -VMName $vmName -ResourceGroupName $config.repositories.rg -Shell "UnixShell" -Script $script
            # Restart the mirror to trigger a pull-then-push
            Start-VM -Name $vmName -ResourceGroupName $config.repositories.rg -ForceRestart
        } catch {
            Add-LogMessage -Level Error "Could not update allowlists for VM '$vmName'. Is it deployed and running?"
        }
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
