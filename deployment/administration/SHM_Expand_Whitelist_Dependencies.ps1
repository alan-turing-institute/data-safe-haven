param(
    [Parameter(Mandatory = $true, HelpMessage = "Mirror type to expand (either 'pypi' or 'cran')")]
    [ValidateSet("pypi", "cran")]
    [string]$MirrorType,
    [Parameter(Mandatory = $true, HelpMessage = "API key for libraries.io")]
    [string]$ApiKey
)

Import-Module $PSScriptRoot/../common/Logging.psm1 -Force


# Get normalised name for a package
# ---------------------------------
function Test-PackageExistence {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of package repository")]
        $Repository,
        [Parameter(Mandatory = $true, HelpMessage = "Name of package to get dependencies for")]
        $Package,
        [Parameter(Mandatory = $true, HelpMessage = "API key for libraries.io")]
        $ApiKey
    )
    try {
        $response = Invoke-RestMethod -URI https://libraries.io/api/${Repository}/${Package}?api_key=${ApiKey} -MaximumRetryCount 12 -RetryIntervalSec 5 -ErrorAction Stop
        return $response
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        Add-LogMessage -Level Error "... $Package could not be found in ${Repository}"
        throw $_.Exception # rethrow the original exception
    }
}


# Get dependencies for all versions of a given package
# ----------------------------------------------------
function Get-Dependencies {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of package repository")]
        $Repository,
        [Parameter(Mandatory = $true, HelpMessage = "Name of package to get dependencies for")]
        $Package,
        [Parameter(Mandatory = $true, HelpMessage = "Versions of package to get dependencies for")]
        $Versions,
        [Parameter(Mandatory = $true, HelpMessage = "API key for libraries.io")]
        $ApiKey,
        [Parameter(Mandatory = $true, HelpMessage = "Hashtable containing cached dependencies")]
        $Cache
    )
    $dependencies = @()
    if ($Package -NotIn $Cache[$Repository].Keys) { $Cache[$Repository][$Package] = [ordered]@{} }
    Add-LogMessage -Level Info "... found $($versions.Count) versions of $Package"
    try {
        foreach ($version in $Versions) {
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
foreach ($packageWhitelist in (Get-Content (Join-Path $PSScriptRoot ".." "dsvm_images" "packages" "packages-${languageName}-${MirrorType}*.list"))) {
    $corePackageList += $packageWhitelist
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
$packageWhitelist = @()
Add-LogMessage -Level Info "Preparing to expand dependencies for $($queue.Count) packages from $MirrorType"
while ($queue.Count) {
    try {
        $unverifiedName = $queue.Dequeue()
        # Check that the package exists and add it to the whitelist if so
        Add-LogMessage -Level Info "Determining canonical name for '$unverifiedName'"
        $response = Test-PackageExistence -Repository $MirrorType -Package $unverifiedName -ApiKey $ApiKey
        $versions = $response.versions | ForEach-Object { $_.number } | Sort-Object
        $packageWhitelist += @($response.Name)
        # Look for dependencies and add them to the queue
        if ($versions) {
            Add-LogMessage -Level Info "... finding dependencies for $($response.Name)"
            $dependencies = Get-Dependencies -Repository $MirrorType -Package $response.Name -Versions $versions -ApiKey $ApiKey -Cache $dependencyCache
            Add-LogMessage -Level Info "... found $($dependencies.Count) dependencies: $dependencies"
            $newPackages = $dependencies | Where-Object { $_ -NotIn $packageWhitelist } | Where-Object { $_ -NotIn $allDependencies } | Where-Object { $_ -NotIn $dependencyCache["unavailable_packages"][$MirrorType] }
            $newPackages | ForEach-Object { $queue.Enqueue($_) }
            $allDependencies += $dependencies
        } else {
            Add-LogMessage -Level Warning "... could not find any versions of $($response.Name)"
        }
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        # If this package could not be found then mark it as unavailable
        Add-LogMessage -Level Error "... marking '$unverifiedName' as unavailable"
        $dependencyCache["unavailable_packages"][$MirrorType] += @($unverifiedName) | Where-Object { $_ -NotIn $dependencyCache["unavailable_packages"][$MirrorType] }
    }
    Add-LogMessage -Level Info "... there are $($packageWhitelist.Count) packages on the expanded whitelist"
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
    $sortedDependencies["unavailable_packages"][$repoName] = @()
    $sortedDependencies["unavailable_packages"][$repoName] += $dependencyCache["unavailable_packages"][$repoName] | Sort-Object | Uniq
}
$sortedDependencies | ConvertTo-Json -Depth 5 | Out-File $dependencyCachePath


# Add a log message for any problematic packages
# ----------------------------------------------
$unneededCorePackages = $corePackageList | Where-Object { $_ -In $allDependencies} | Sort-Object | Uniq
if ($unneededCorePackages) {
    Add-LogMessage -Level Warning "... found $($unneededCorePackages.Count) core packages that would have been included as dependencies: $unneededCorePackages"
}
$unavailablePackages = $sortedDependencies["unavailable_packages"][$MirrorType]
if ($unavailablePackages) {
    Add-LogMessage -Level Warning "... ignored $($unavailablePackages.Count) dependencies that could not be found in ${MirrorType}: $unavailablePackages"
}


# Write the full package list to the expanded whitelist
# -----------------------------------------------------
Add-LogMessage -Level Info "Writing $($packageWhitelist.Count) packages to the expanded whitelist..."
$packageWhitelist | Sort-Object | Uniq | Out-File $fullWhitelistPath
