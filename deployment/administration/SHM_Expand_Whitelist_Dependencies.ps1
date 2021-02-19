param(
    [Parameter(Mandatory = $true, HelpMessage = "Mirror type to expand (either 'pypi' or 'cran')")]
    [ValidateSet("pypi", "cran")]
    [string]$MirrorType,
    [Parameter(Mandatory = $true, HelpMessage = "API key for libraries.io")]
    [string]$ApiKey,
    [Parameter(Mandatory = $false, HelpMessage = "Only consider the most recent NVersions.")]
    [int]$NVersions = -1
)

Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


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
        $response = Invoke-RestMethod -Uri https://libraries.io/api/${Repository}/${Package}?api_key=${ApiKey} -MaximumRetryCount 15 -RetryIntervalSec 5 -ErrorAction Stop
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
        [string]$Repository,
        [Parameter(Mandatory = $true, HelpMessage = "Name of package to get dependencies for")]
        [string]$Package,
        [Parameter(Mandatory = $true, HelpMessage = "Versions of package to get dependencies for")]
        $Versions,
        [Parameter(Mandatory = $true, HelpMessage = "API key for libraries.io")]
        [string]$ApiKey,
        [Parameter(Mandatory = $true, HelpMessage = "Hashtable containing cached dependencies")]
        $Cache,
        [Parameter(Mandatory = $true, HelpMessage = "Only consider the most recent NVersions. Set to -1 to consider all versions.")]
        [int]$NVersions

    )
    $dependencies = @()
    if ($Package -notin $Cache[$Repository].Keys) { $Cache[$Repository][$Package] = [ordered]@{} }
    Add-LogMessage -Level Info "... found $($Versions.Count) versions of $Package"
    $MostRecentVersions = ($NVersions -gt 0) ? ($Versions | Select-Object -Last $NVersions) : $Versions
    try {
        foreach ($Version in $MostRecentVersions) {
            if ($Version -notin $Cache[$Repository][$Package].Keys) {
                $response = Invoke-RestMethod -Uri https://libraries.io/api/${Repository}/${Package}/${Version}/dependencies?api_key=${ApiKey} -MaximumRetryCount 15 -RetryIntervalSec 5 -ErrorAction Stop
                $Cache[$Repository][$Package][$Version] = @($response.dependencies | Where-Object { $_.requirements -ne "extra" } | Where-Object { $_.kind -ne "suggests" } | ForEach-Object { $_.name.Replace(";", "") }) | Sort-Object -Unique
            }
            $dependencies += $Cache[$Repository][$Package][$Version]
        }
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        Add-LogMessage -Level Error "... could not load dependencies for all versions of $Package"
    }
    if (-not $dependencies) { return @() }
    return $($dependencies | Where-Object { $_ } | Sort-Object -Unique)
}


# Load appropriate whitelists
# ---------------------------
$languageName = @{cran = "r"; pypi = "python" }[$MirrorType]
$coreWhitelistPath = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" "whitelist-core-${languageName}-${MirrorType}-tier3.list"
$fullWhitelistPath = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" "whitelist-full-${languageName}-${MirrorType}-tier3.list"
$dependencyCachePath = Join-Path $PSScriptRoot ".dependency_cache.json"

# Combine base image package lists with the core whitelist to construct a single list of core packages
# ----------------------------------------------------------------------------------------------------
$corePackageList = Get-Content $coreWhitelistPath
foreach ($buildtimePackageList in (Get-Content (Join-Path $PSScriptRoot ".." "dsvm_images" "packages" "packages-${languageName}-${MirrorType}*.list"))) {
    $corePackageList += $buildtimePackageList
}
$corePackageList = $corePackageList | Sort-Object -Unique


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
if ($MirrorType -notin $dependencyCache.Keys) { $dependencyCache[$MirrorType] = [ordered]@{} }
if ("unavailable_packages" -notin $dependencyCache.Keys) { $dependencyCache["unavailable_packages"] = [ordered]@{} }
if ($MirrorType -notin $dependencyCache["unavailable_packages"].Keys) { $dependencyCache["unavailable_packages"][$MirrorType] = @() }


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
            $dependencies = Get-Dependencies -Repository $MirrorType -Package $response.Name -Versions $versions -ApiKey $ApiKey -Cache $dependencyCache -NVersions $NVersions
            Add-LogMessage -Level Info "... found $($dependencies.Count) dependencies: $dependencies"
            $newPackages = $dependencies | Where-Object { $_ -notin $packageWhitelist } | Where-Object { $_ -notin $allDependencies } | Where-Object { $_ -notin $dependencyCache["unavailable_packages"][$MirrorType] }
            $newPackages | ForEach-Object { $queue.Enqueue($_) }
            $allDependencies += $dependencies
        } else {
            Add-LogMessage -Level Warning "... could not find any versions of $($response.Name)"
        }
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        # If this package could not be found then mark it as unavailable
        Add-LogMessage -Level Error "... marking '$unverifiedName' as unavailable"
        $dependencyCache["unavailable_packages"][$MirrorType] += @($unverifiedName) | Where-Object { $_ -notin $dependencyCache["unavailable_packages"][$MirrorType] }
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
            $sortedDependencies[$repoName][$pkgName][$version] = @($dependencyCache[$repoName][$pkgName][$version] | Sort-Object -Unique)
        }
    }
}
foreach ($repoName in $($dependencyCache["unavailable_packages"].Keys | Sort-Object)) {
    $sortedDependencies["unavailable_packages"][$repoName] = @()
    $sortedDependencies["unavailable_packages"][$repoName] += $dependencyCache["unavailable_packages"][$repoName] | Sort-Object -Unique
}
$sortedDependencies | ConvertTo-Json -Depth 5 | Out-File $dependencyCachePath


# Add a log message for any problematic packages
# ----------------------------------------------
$unneededCorePackages = $corePackageList | Where-Object { $_ -In $allDependencies } | Sort-Object -Unique
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
$packageWhitelist | Sort-Object -Unique | Out-File $fullWhitelistPath
