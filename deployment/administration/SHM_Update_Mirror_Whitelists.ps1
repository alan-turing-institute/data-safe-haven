param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (usually a number e.g enter '9' for DSG9)")]
    [string]$shmId,
    [Parameter(Mandatory = $false, HelpMessage = "Path to directory containing whitelist files (default: '<repo root>/environment_configs/package_lists')")]
    [string]$whitelistDirectory = $null
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig $shmId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName


# Common variable names
# ---------------------
$mirrorTypes = @("PyPI", "CRAN")
$tier = "3"  # currently only Tier-3 mirrors have whitelists
if (-Not $whitelistDirectory) { $whitelistDirectory = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" }


# Update all external package mirrors
# -----------------------------------
foreach ($mirrorType in $mirrorTypes) {
    $fullMirrorType = "${mirrorType}".ToLower().Replace("cran", "r-cran").Replace("pypi", "python-pypi")
    $whitelistPath = Join-Path $whitelistDirectory "whitelist-core-${fullMirrorType}-tier${tier}.list".ToLower() -Resolve
    $whiteList = Get-Content $whitelistPath -Raw -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Failure "Could not find whitelist at '$whitelistPath'"
    } else {
        # Update the whitelist with the new set of packages
        Add-LogMessage -Level Info "Using whitelist from '$whitelistPath'"
        $script = "#! /bin/bash`n"
        $script += ": > /home/mirrordaemon/package_whitelist.txt`n"  # ':' is the shell no-op command
        foreach ($package in $whiteList -split "`n") {
            $script += "echo $package >> /home/mirrordaemon/package_whitelist.txt`n"
        }
        $script += "sed -i '/^$/d' /home/mirrordaemon/package_whitelist.txt`n"  # remove empty lines
        $script += "echo `"There are `$(wc -l /home/mirrordaemon/package_whitelist.txt | cut -d' ' -f1)`" packages on the whitelist`n"

        # PyPI also needs us to run the script which updates /etc/bandersnatch.conf
        if ($MirrorType.ToLower() -eq "pypi") {
            $script += "python3 /home/mirrordaemon/update_bandersnatch_config.py`n"
        }

        # Run the script on the mirror VM
        $vmName = "$MirrorType-EXTERNAL-MIRROR-TIER-$tier".ToUpper()
        Add-LogMessage -Level Info "Updating whitelist on $vmName"
        $result = Invoke-RemoteScript -VMName $vmName -ResourceGroupName $config.mirrors.rg -Shell "UnixShell" -Script $script
        Write-Output $result.Value

        # Restart the mirror to trigger a pull-then-push
        Enable-AzVM -Name $vmName -ResourceGroupName $config.mirrors.rg
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
