param(
    [Parameter(Mandatory = $true, HelpMessage = "Mirror type to expand (either 'pypi' or 'cran')")]
    [ValidateSet("pypi", "cran")]
    [string]$MirrorType,
    [Parameter(Mandatory = $true, HelpMessage = "API key for libraries.io")]
    [string]$ApiKey
)

Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Filter out any dependencies that we do not want to add to the whitelist
# -----------------------------------------------------------------------
function Select-ResolvableDependencies {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of package repository")]
        $Repository,
        [Parameter(Mandatory = $true, HelpMessage = "List of dependencies to filter")]
        $Dependencies
    )
    if ($Repository -eq "cran") {
        $packagesToIgnore = @("base", "compiler", "graphics", "grDevices", "methods", "R", "splines", "stats", "tools", "utils") # these are core packages
        $Dependencies = $Dependencies | Where-Object { $_ -NotIn $packagesToIgnore }
    }
    return $Dependencies
}


# Get dependencies for all versions of a given package
# ----------------------------------------------------
function Get-Dependencies {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of package repository")]
        $Repository,
        [Parameter(Mandatory = $true, HelpMessage = "Name of package to get dependencies for")]
        $Package,
        [Parameter(Mandatory = $true, HelpMessage = "API key for libraries.io")]
        $ApiKey
    )
    $dependencies = @()
    try {
        $response = Invoke-RestMethod -URI https://libraries.io/api/${Repository}/${Package}?api_key=${ApiKey} -MaximumRetryCount 5 -RetryIntervalSec 30 -ErrorAction Stop
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        Add-LogMessage -Level Error "... $Package could not be found in ${Repository}"
        throw [System.IO.FileNotFoundException]::new("Could not find package: $Package")
    }
    $versions = $response.versions | ForEach-Object { $_.number }
    Add-LogMessage -Level Info "... found $($versions.Count) versions of $Package"
    try {
        foreach ($version in $versions) {
            $response = Invoke-RestMethod -URI https://libraries.io/api/${Repository}/${Package}/${version}/dependencies?api_key=${ApiKey} -MaximumRetryCount 5 -RetryIntervalSec 30 -ErrorAction Stop
            $dependencies += ($response.dependencies | ForEach-Object { $_.name })
            Start-Sleep 1 # wait for one second between requests to respect the API query limit
        }
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        Add-LogMessage -Level Error "... could not load dependencies for all versions of $Package"
    }
    if (-Not $dependencies) { return @() }
    return Select-ResolvableDependencies -Repository $Repository -Dependencies ($dependencies | Sort-Object | Uniq)
}


# Load appropriate whitelists
# ---------------------------
$languageName = @{cran = "r"; pypi = "python"}[$MirrorType]
$coreWhitelistPath = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" "whitelist-core-${languageName}-${MirrorType}-tier3.list"
$fullWhitelistPath = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" "whitelist-full-${languageName}-${MirrorType}-tier3.list"


# Combine base image package lists with the core whitelist to construct a single list of core packages
# ----------------------------------------------------------------------------------------------------
$corePackageList = Get-Content $coreWhitelistPath
foreach ($packageList in (Get-Content (Join-Path $PSScriptRoot ".." "dsvm_images" "packages" "packages-${languageName}-${MirrorType}*.list"))) {
    $corePackageList += $packageList
}
$corePackageList = $corePackageList | Sort-Object | Uniq


# Initialise the package queue
# ----------------------------
$queue = New-Object System.Collections.Queue
$corePackageList | ForEach-Object { $queue.Enqueue($_) }
$allDependencies = @()


# Resolve packages iteratively until the queue is empty
# -----------------------------------------------------
$packageList = $corePackageList
Add-LogMessage -Level Info "Preparing to expand dependencies for $($packageList.Count) packages from $MirrorType"
while ($queue.Count) {
    $package = $queue.Dequeue()
    Add-LogMessage -Level Info "Finding dependencies for '$package'"
    try {
        # Add dependencies from this package
        $dependencies = Get-Dependencies -Repository $MirrorType -Package $Package -ApiKey $ApiKey
        Add-LogMessage -Level Info "... found $($dependencies.Count) dependencies: $dependencies"
        $allDependencies += $dependencies
        $newPackages = $dependencies | Where-Object { $_ -NotIn $packageList }
        $packageList += $newPackages
        $newPackages | ForEach-Object { $queue.Enqueue($_) }
    } catch [System.IO.FileNotFoundException] {
        # If this package could not be found then instead remove the package from the expanded list
        Add-LogMessage -Level Error "... removing $Package from the expanded whitelist"
        $packageList = $packageList | Where-Object { $_ -ne $package }
    }
    Add-LogMessage -Level Info "... there are $($packageList.Count) packages on the expanded whitelist"
    Add-LogMessage -Level Info "... there are $($queue.Count) packages in the queue"
}


# Add a log message for any unnecessary core packages
# ---------------------------------------------------
$unneededCorePackages = $corePackageList | Where-Object { $_ -In $allDependencies}
if ($unneededCorePackages) {
    Add-LogMessage -Level Warning "... found $($unneededCorePackages.Count) core packages that would have been included as dependencies: $unneededCorePackages"
}

# Remove any unnecesary packages from the core whitelist
# ------------------------------------------------------
$corePackages = Get-Content $coreWhitelistPath
$corePackages | Sort-Object | Uniq | Where-Object { $_ -NotIn $unneededCorePackages } | Out-File $coreWhitelistPath


# Write the full package list to the expanded whitelist
# -----------------------------------------------------
Add-LogMessage -Level Info "Writing $($packageList.Count) packages to the expanded whitelist..."
$packageList | Sort-Object | Uniq | Out-File $fullWhitelistPath
