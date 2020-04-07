param(
    [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a number e.g enter '9' for DSG9)")]
    [string]$shmId
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


# Update all external package mirrors
# -----------------------------------
foreach ($mirrorType in $mirrorTypes) {
    $whitelistPath = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" "tier${tier}_${mirrorType}_whitelist.list".ToLower() -Resolve
    $whiteList = Get-Content $whitelistPath -Raw -ErrorVariable notExists -ErrorAction SilentlyContinue
    if ($notExists) {
        Add-LogMessage -Level Failure "Could not find whitelist $whitelistPath"
    } else {
        # Update the whitelist with the new set of packages
        $script = "#! /bin/bash`n"
        $script += "echo '' > /home/mirrordaemon/package_whitelist.txt`n"
        foreach ($package in $whiteList -split "`n") {
            $script += "echo $package >> /home/mirrordaemon/package_whitelist.txt`n"
        }
        $script += "echo `"There are `$(wc -l /home/mirrordaemon/package_whitelist.txt | cut -d' ' -f1)`" packages on the whitelist`n"

        # PyPI also needs us to run the script which updates /etc/bandersnatch.conf
        if ($MirrorType.ToLower() -eq "pypi") {
            $script += "python3 /home/mirrordaemon/update_whitelist.py`n"
        }

        # Run the script on the mirror VM
        $vmName = "$MirrorType-EXTERNAL-MIRROR-TIER-$tier".ToUpper()
        Add-LogMessage -Level Info "Updating whitelist on $vmName"
        $result = Invoke-RemoteScript -VMName $vmName -ResourceGroupName $config.mirrors.rg -Shell "UnixShell" -Script $script
        Write-Output $result.Value
    }
}


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
