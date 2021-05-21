param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "Path to directory containing allowlist files (default: '<repo root>/environment_configs/package_lists')")]
    [string]$allowlistDirectory = $null
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmConfig -shmId $shmId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.subscriptionName -ErrorAction Stop


# Common variable names
# ---------------------
$mirrorTypes = @("PyPI", "CRAN")
$tier = "3"  # currently only Tier-3 mirrors have allowlists
if (-Not $allowlistDirectory) { $allowlistDirectory = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" }


# Update all external package mirrors
# -----------------------------------
foreach ($mirrorType in $mirrorTypes) {
    $fullMirrorType = "${mirrorType}".ToLower().Replace("cran", "r-cran").Replace("pypi", "python-pypi")
    $allowlistPath = Join-Path $allowlistDirectory "allowlist-full-${fullMirrorType}-tier${tier}.list".ToLower() -Resolve
    $allowList = Get-Content $allowlistPath -Raw -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Failure "Could not find allowlist at '$allowlistPath'"
    } else {
        # Update the allowlist with the new set of packages
        Add-LogMessage -Level Info "Using allowlist from '$allowlistPath'"
        $script = "#! /bin/bash`n"
        $script += ": > /home/mirrordaemon/package_allowlist.txt`n"  # ':' is the shell no-op command
        foreach ($package in $allowList -split "`n") {
            $script += "echo $package >> /home/mirrordaemon/package_allowlist.txt`n"
        }
        $script += "sed -i '/^$/d' /home/mirrordaemon/package_allowlist.txt`n"  # remove empty lines
        $script += "echo `"There are `$(wc -l /home/mirrordaemon/package_allowlist.txt | cut -d' ' -f1)`" packages on the allowlist`n"

        # PyPI also needs us to run the script which updates /etc/bandersnatch.conf
        if ($MirrorType.ToLower() -eq "pypi") {
            $script += "python3 /home/mirrordaemon/update_bandersnatch_config.py`n"
        }

        # Run the script on the mirror VM
        $vmName = "$MirrorType-EXTERNAL-MIRROR-TIER-$tier".ToUpper()
        Add-LogMessage -Level Info "Updating allowlist on $vmName"
        $null = Invoke-RemoteScript -VMName $vmName -ResourceGroupName $config.mirrors.rg -Shell "UnixShell" -Script $script

        # Restart the mirror to trigger a pull-then-push
        Start-VM -Name $vmName -ResourceGroupName $config.mirrors.rg -ForceRestart
    }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
