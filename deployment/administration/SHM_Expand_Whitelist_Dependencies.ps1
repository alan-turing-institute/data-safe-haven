param(
    [Parameter(Mandatory = $true, HelpMessage = "Mirror type to expand (either 'pypi' or 'cran')")]
    [ValidateSet("pypi", "cran")]
    [string]$MirrorType,
    [Parameter(Mandatory = $true, HelpMessage = "API key for libraries.io")]
    [string]$ApiKey
)

Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get dependencies for all versions of a given package
# ----------------------------------------------------
function Get-Dependencies {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of package repository")]
        $Repository,
        [Parameter(Mandatory = $true, HelpMessage = "Name of package to get dependencies for")]
        $Package,
        [Parameter(Mandatory = $true, HelpMessage = "API key for libraries.io")]
        $ApiKey,
        [Parameter(Mandatory = $true, HelpMessage = "Hashtable containing cached dependencies")]
        $Cache
    )
    $dependencies = @()
    try {
        $response = Invoke-RestMethod -URI https://libraries.io/api/${Repository}/${Package}?api_key=${ApiKey} -MaximumRetryCount 12 -RetryIntervalSec 5 -ErrorAction Stop
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        Add-LogMessage -Level Error "... $Package could not be found in ${Repository}"
        throw $_.Exception # rethrow the original exception
    }
    if ($Package -NotIn $Cache[$Repository].Keys) { $Cache[$Repository][$Package] = [ordered]@{} }
    $versions = $response.versions | ForEach-Object { $_.number } | Sort-Object
    Add-LogMessage -Level Info "... found $($versions.Count) versions of $Package"
    try {
        foreach ($version in $versions) {
            if ($version -NotIn $Cache[$Repository][$Package].Keys) {
                $response = Invoke-RestMethod -URI https://libraries.io/api/${Repository}/${Package}/${version}/dependencies?api_key=${ApiKey} -MaximumRetryCount 12 -RetryIntervalSec 5 -ErrorAction Stop
                $Cache[$Repository][$Package][$version] = @($response.dependencies | Where-Object { $_.kind -ne "suggests" } | ForEach-Object { $_.name }) | Sort-Object | Uniq
            }
            $dependencies += $Cache[$Repository][$Package][$version]
        }
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        Add-LogMessage -Level Error "... could not load dependencies for all versions of $Package"
    }
    if (-Not $dependencies) { return @() }
    return $($dependencies | Sort-Object | Uniq)
}


# Load appropriate whitelists
# ---------------------------
$languageName = @{cran = "r"; pypi = "python"}[$MirrorType]
$coreWhitelistPath = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" "whitelist-core-${languageName}-${MirrorType}-tier3.list"
$fullWhitelistPath = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" "whitelist-full-${languageName}-${MirrorType}-tier3.list"
$dependencyCachePath = Join-Path $PSScriptRoot ".dependency_cache.json"

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


# Load any previously-cached dependencies
$dependencyCache = [ordered]@{}
if (Test-Path $dependencyCachePath -PathType Leaf) {
    $dependencyCache = Get-Content $dependencyCachePath | ConvertFrom-Json -AsHashtable
}
if ($MirrorType -NotIn $dependencyCache.Keys) { $dependencyCache[$MirrorType] = [ordered]@{} }
if ("unavailable_packages" -NotIn $dependencyCache.Keys) { $dependencyCache["unavailable_packages"] = [ordered]@{} }
if ($MirrorType -NotIn $dependencyCache["unavailable_packages"].Keys) { $dependencyCache["unavailable_packages"][$MirrorType] = @() }


# Resolve packages iteratively until the queue is empty
# -----------------------------------------------------
$packageList = $corePackageList
Add-LogMessage -Level Info "Preparing to expand dependencies for $($packageList.Count) packages from $MirrorType"
while ($queue.Count) {
    $package = $queue.Dequeue()
    Add-LogMessage -Level Info "Finding dependencies for '$package'"
    try {
        # Add dependencies from this package
        $dependencies = Get-Dependencies -Repository $MirrorType -Package $package -ApiKey $ApiKey -Cache $dependencyCache
        Add-LogMessage -Level Info "... found $($dependencies.Count) dependencies: $dependencies"
        $allDependencies += $dependencies
        $newPackages = $dependencies | Where-Object { $_ -NotIn $packageList } | Where-Object { $_ -NotIn $unavailablePackages }
        $packageList += $newPackages
        $newPackages | ForEach-Object { $queue.Enqueue($_) }
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        # If this package could not be found then instead remove the package from the expanded list
        Add-LogMessage -Level Error "... removing $package from the expanded whitelist"
        $packageList = $packageList | Where-Object { $_ -ne $package }
        $dependencyCache["unavailable_packages"][$MirrorType] += @($package) | Where-Object { $_ -NotIn $dependencyCache["unavailable_packages"][$MirrorType] }
    }
    Add-LogMessage -Level Info "... there are $($packageList.Count) packages on the expanded whitelist"
    Add-LogMessage -Level Info "... there are $($queue.Count) packages in the queue"
    # Write to the dependency file after each package in case the script terminates early
    $dependencyCache | ConvertTo-Json -Depth 5 | Out-File $dependencyCachePath
}

# After processing all packages ensure that the dependencies cache is sorted
Add-LogMessage -Level Info "Sorting dependency cache..."
$sortedDependencies = [ordered]@{}
foreach ($repoName in $($dependencyCache.Keys | Sort-Object)) {
    $sortedDependencies[$repoName] = [ordered]@{}
    foreach ($pkgName in $($dependencyCache[$repoName].Keys | Sort-Object)) {
        $sortedDependencies[$repoName][$pkgName] = [ordered]@{}
        foreach ($version in $($dependencyCache[$repoName][$pkgName].Keys | Sort-Object)) {
            $sortedDependencies[$repoName][$pkgName][$version] = @($dependencyCache[$repoName][$pkgName][$version] | Sort-Object | Uniq)
        }
    }
}
foreach ($repoName in $($dependencyCache["unavailable_packages"].Keys | Sort-Object)) {
    $sortedDependencies["unavailable_packages"][$repoName] = $dependencyCache["unavailable_packages"][$repoName] | Sort-Object | Uniq
}
$sortedDependencies | ConvertTo-Json -Depth 5 | Out-File $dependencyCachePath


# Add a log message for any problematic packages
# ----------------------------------------------
$unneededCorePackages = $corePackageList | Where-Object { $_ -In $allDependencies} | Sort-Object | Uniq
if ($unneededCorePackages) {
    Add-LogMessage -Level Warning "... found $($unneededCorePackages.Count) core packages that would have been included as dependencies: $unneededCorePackages"
}
if ($sortedDependencies["unavailable_packages"][$MirrorType]) {
    $unavailablePackages = $sortedDependencies["unavailable_packages"][$MirrorType]
    Add-LogMessage -Level Warning "... removed $($unavailablePackages.Count) dependencies that could not be found in ${MirrorType}: $($unavailablePackages | Sort-Object | Uniq)"
}


# Write the full package list to the expanded whitelist
# -----------------------------------------------------
Add-LogMessage -Level Info "Writing $($packageList.Count) packages to the expanded whitelist..."
$packageList | Sort-Object | Uniq | Out-File $fullWhitelistPath
