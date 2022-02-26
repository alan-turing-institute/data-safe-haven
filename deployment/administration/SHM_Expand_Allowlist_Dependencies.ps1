param(
    [Parameter(Mandatory = $true, HelpMessage = "Mirror type to expand (either 'pypi' or 'cran')")]
    [ValidateSet("pypi", "cran")]
    [string]$Repository,
    [Parameter(Mandatory = $true, HelpMessage = "API key for libraries.io")]
    [string]$ApiKey,
    [Parameter(Mandatory = $false, HelpMessage = "Only consider the most recent NVersions.")]
    [int]$NVersions = -1,
    [Parameter(Mandatory = $false, HelpMessage = "Timeout in minutes.")]
    [int]$TimeoutMinutes = 600,
    [Parameter(Mandatory = $false, HelpMessage = "Do not use a cache file.")]
    [switch]$NoCache
)

Import-Module $PSScriptRoot/../common/Logging -Force -ErrorAction Stop


# Get normalised name for a package
# ---------------------------------
function Test-PackageExistence {
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Name of package repository")]
        [string]$Repository,
        [Parameter(Mandatory = $true, HelpMessage = "Name of package to get dependencies for")]
        [string]$Package,
        [Parameter(Mandatory = $false, HelpMessage = "Repository ID for RStudio package manager")]
        [string]$RepositoryId,
        [Parameter(Mandatory = $false, HelpMessage = "API key for libraries.io")]
        [string]$ApiKey
    )
    try {
        if ($Repository -eq "pypi") {
            # The best PyPI results come from the package JSON files
            $response = Invoke-RestMethod -Uri "https://pypi.org/${Repository}/${Package}/json" -MaximumRetryCount 4 -RetryIntervalSec 1 -ErrorAction Stop
            $versions = $response.releases | Get-Member -MemberType NoteProperty | ForEach-Object { $_.Name }
            $name = $response.info.name
        } elseif ($Repository -eq "cran") {
            # Use the RStudio package manager for CRAN packages
            $response = Invoke-RestMethod -Uri "https://packagemanager.rstudio.com/__api__/repos/${RepositoryId}/packages?name=${Package}&case_insensitive=true" -MaximumRetryCount 4 -RetryIntervalSec 1 -ErrorAction Stop
            $name = $response.name
            $response = Invoke-RestMethod -Uri "https://packagemanager.rstudio.com/__api__/repos/${RepositoryId}/packages/${name}" -MaximumRetryCount 4 -RetryIntervalSec 1 -ErrorAction Stop
            $versions = @($response.version) + ($response.archived | ForEach-Object { $_.version })
        } else {
            # For other repositories we use libraries.io
            # As we are rate-limited to 60 requests per minute this request can fail. If it does, we retry every few seconds for 1 minute
            $response = Invoke-RestMethod -Uri "https://libraries.io/api/${Repository}/${Package}?api_key=${ApiKey}" -MaximumRetryCount 16 -RetryIntervalSec 4 -ErrorAction Stop
            $versions = $response.versions | ForEach-Object { $_.number }
            $name = $response.Name
        }
        return @{
            versions = ($versions | Sort-Object -Unique)
            name     = $name
        }
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
        [Parameter(Mandatory = $true, HelpMessage = "Hashtable containing cached dependencies")]
        $Cache,
        [Parameter(Mandatory = $true, HelpMessage = "Only consider the most recent NVersions. Set to -1 to consider all versions.")]
        [int]$NVersions,
        [Parameter(Mandatory = $false, HelpMessage = "API key for libraries.io")]
        [string]$ApiKey
    )
    $dependencies = @()
    if ($Package -notin $Cache[$Repository].Keys) { $Cache[$Repository][$Package] = [ordered]@{} }
    Add-LogMessage -Level Info "... found $($Versions.Count) versions of $Package"
    $MostRecentVersions = ($NVersions -gt 0) ? ($Versions | Select-Object -Last $NVersions) : $Versions
    foreach ($Version in $MostRecentVersions) {
        if ($Version -notin $Cache[$Repository][$Package].Keys) {
            try {
                if ($Repository -eq "pypi") {
                    # The best PyPI results come from the package JSON files
                    $response = Invoke-RestMethod -Uri "https://pypi.org/${Repository}/${Package}/${Version}/json" -MaximumRetryCount 4 -RetryIntervalSec 1 -ErrorAction Stop
                    $Cache[$Repository][$Package][$Version] = @($response.info.requires_dist | Where-Object { $_ -and ($_ -notmatch "extra ==") } | ForEach-Object { ($_ -split '[;[( ><=]')[0].Trim() } | Sort-Object -Unique)
                } else {
                    # For other repositories we use libraries.io
                    try {
                        # Make an initial attempt without any retries
                        $response = Invoke-RestMethod -Uri "https://libraries.io/api/${Repository}/${Package}/${Version}/dependencies?api_key=${ApiKey}" -ErrorAction Stop
                    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
                        # If the failure is due to TooManyRequests (429) then retry for 1 minute
                        if ($_.Exception.Response.StatusCode -eq "TooManyRequests") {
                            $response = Invoke-RestMethod -Uri "https://libraries.io/api/${Repository}/${Package}/${Version}/dependencies?api_key=${ApiKey}" -MaximumRetryCount 16 -RetryIntervalSec 4 -ErrorAction Stop
                        }
                    }
                    $Cache[$Repository][$Package][$Version] = @($response.dependencies | Where-Object { $_.requirements -ne "extra" } | Where-Object { $_.kind -ne "suggests" } | ForEach-Object { $_.name.Replace(";", "") }) | Sort-Object -Unique
                }
            } catch {
                Add-LogMessage -Level Warning "No dependencies found for ${Package} (${Version}) from ${Repository}!"
            }
        }
        $dependencies += $Cache[$Repository][$Package][$Version]
    }
    if (-not $dependencies) { return @() }
    return $($dependencies | Where-Object { $_ } | Sort-Object -Unique)
}


# Load list of core packages
# --------------------------
$languageName = @{cran = "r"; pypi = "python" }[$Repository]
$coreAllowlistPath = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" "allowlist-core-${languageName}-${Repository}-tier3.list"
$fullAllowlistPath = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" "allowlist-full-${languageName}-${Repository}-tier3.list"
$dependencyCachePath = Join-Path $PSScriptRoot ".." ".." "environment_configs" "package_lists" "dependency-cache.json"
$corePackageList = Get-Content $coreAllowlistPath | Sort-Object -Unique


# Initialise the package queue
# ----------------------------
$queue = New-Object System.Collections.Queue
$corePackageList | ForEach-Object { $queue.Enqueue($_) }
$allDependencies = @()


# Load any previously-cached dependencies
# ---------------------------------------
$dependencyCache = [ordered]@{}
if (-not $NoCache) {
    if (Test-Path $dependencyCachePath -PathType Leaf) {
        $dependencyCache = Get-Content $dependencyCachePath | ConvertFrom-Json -AsHashtable
    }
}
if ($Repository -notin $dependencyCache.Keys) { $dependencyCache[$Repository] = [ordered]@{} }
if ("unavailable_packages" -notin $dependencyCache.Keys) { $dependencyCache["unavailable_packages"] = [ordered]@{} }
if ($Repository -notin $dependencyCache["unavailable_packages"].Keys) { $dependencyCache["unavailable_packages"][$Repository] = @() }


# Load RStudio repository ID if relevant
# --------------------------------------
if ($Repository -eq "cran") {
    $response = Invoke-RestMethod -Uri "https://packagemanager.rstudio.com/__api__/repos" -MaximumRetryCount 4 -RetryIntervalSec 1 -ErrorAction Stop
    $RepositoryId = $response | Where-Object { $_.name -eq $Repository } | ForEach-Object { $_.id } | Select-Object -First 1
} else {
    $RepositoryId = $null
}


# Resolve packages iteratively until the queue is empty
# -----------------------------------------------------
$packageAllowlist = @()
Add-LogMessage -Level Info "Preparing to expand dependencies for $($queue.Count) package(s) from $Repository"
$LatestTime = (Get-Date) + (New-TimeSpan -Minutes $TimeoutMinutes)
while ($queue.Count) {
    try {
        $unverifiedName = $queue.Dequeue()
        # Ignore this packages if it has already been processed
        if ($unverifiedName -in $packageAllowlist) { continue }
        # Check that the package exists and add it to the allowlist if so
        Add-LogMessage -Level Info "Looking for '${unverifiedName}' in ${Repository}..."
        $packageData = Test-PackageExistence -Repository $Repository -Package $unverifiedName -ApiKey $ApiKey -RepositoryId $RepositoryId
        if ($packageData.name -cne $unverifiedName) {
            Add-LogMessage -Level Warning "Package '${unverifiedName}' should be '$($packageData.name)'"
        }
        $packageAllowlist += @($packageData.name)
        # Look for dependencies and add them to the queue
        if ($packageData.versions) {
            Add-LogMessage -Level Info "... finding dependencies for $($packageData.name)"
            $dependencies = Get-Dependencies -Repository $Repository -Package $packageData.name -Versions $packageData.versions -ApiKey $ApiKey -Cache $dependencyCache -NVersions $NVersions
            Add-LogMessage -Level Info "... found $($dependencies.Count) dependencies: $dependencies"
            $newPackages = $dependencies | Where-Object { $_ -notin $packageAllowlist } | Where-Object { $_ -notin $allDependencies } | Where-Object { $_ -notin $dependencyCache["unavailable_packages"][$Repository] }
            $newPackages | ForEach-Object { $queue.Enqueue($_) }
            $allDependencies += $dependencies
        } else {
            Add-LogMessage -Level Warning "... could not find any versions of $($packageData.name)"
        }
    } catch [Microsoft.PowerShell.Commands.HttpResponseException] {
        # If this package could not be found then mark it as unavailable
        Add-LogMessage -Level Error "... marking '$unverifiedName' as unavailable"
        $dependencyCache["unavailable_packages"][$Repository] += @($unverifiedName) | Where-Object { $_ -notin $dependencyCache["unavailable_packages"][$Repository] }
    }
    Add-LogMessage -Level Info "... there are $($packageAllowlist.Count) package(s) on the allowlist"
    Add-LogMessage -Level Info "... there are $($queue.Count) package(s) in the queue"
    # Write to the dependency file after each package in case the script terminates early
    if (-not $NoCache) {
        $dependencyCache | ConvertTo-Json -Depth 99 | Out-File $dependencyCachePath
    }
    # If we have exceeded the timeout then set the TIMEOUT_REACHED switch and break even if there are packages left in the queue
    if ((Get-Date) -ge $LatestTime) {
        Add-LogMessage -Level Error "Maximum runtime exceeded with $($queue.Count) package(s) left in the queue!"
        Write-Output "TIMEOUT_REACHED=1" | Out-File -FilePath $Env:GITHUB_ENV -Encoding utf-8 -Append
        break
    }
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
if (-not $NoCache) {
    $sortedDependencies | ConvertTo-Json -Depth 99 | Out-File $dependencyCachePath
}


# Add a log message for any problematic packages
# ----------------------------------------------
$unneededCorePackages = $corePackageList | Where-Object { $_ -In $allDependencies } | Sort-Object -Unique
if ($unneededCorePackages) {
    Add-LogMessage -Level Info "... found $($unneededCorePackages.Count) explicitly requested package(s) that would have been allowed as dependencies of other packages: $unneededCorePackages"
}
$unavailablePackages = $sortedDependencies["unavailable_packages"][$Repository]
if ($unavailablePackages) {
    Add-LogMessage -Level Warning "... ignored $($unavailablePackages.Count) dependencies that could not be found in ${Repository}: $unavailablePackages"
}


# Write the full package list to the allowlist
# --------------------------------------------
Add-LogMessage -Level Info "Writing $($packageAllowlist.Count) package(s) to the allowlist..."
$packageAllowlist | Sort-Object -Unique | Out-File $fullAllowlistPath
