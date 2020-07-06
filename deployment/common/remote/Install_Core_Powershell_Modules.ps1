# Get existing modules
# --------------------
$existingModuleNames = Get-Module -ListAvailable | ForEach-Object { $_.Name }


# Install NuGet
# -------------
$provider = "NuGet"
Write-Output "Installing $provider..."
Install-PackageProvider -Name $provider -Force 2>&1 | Out-Null
$installedProvider = Get-PackageProvider -ListAvailable -Name $provider | Select-Object -First 1
if ($installedProvider) {
    Write-Output " [o] $provider $($installedProvider.Version.ToString()) is installed"
} else {
    Write-Output " [x] Failed to install $provider!"
}


# Add the PSGallery to the list of trusted repositories
# -----------------------------------------------------
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted


# Install core modules
# --------------------
foreach ($moduleName in @("PackageManagement", "PowerShellGet", "PSWindowsUpdate")) {
    Write-Output "Installing $moduleName..."
    # NB. We skip publisher check as the PowerShellGet catalog signature is broken
    Install-Module -Name $moduleName -Repository PSGallery -AllowClobber -SkipPublisherCheck -Force 2>&1 3>&1 | Out-Null
    Update-Module -Name $moduleName -Force 2>&1 3>&1 | Out-Null
    $installedModule = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1
    if ($installedModule) {
        Write-Output " [o] $moduleName $($installedModule.Version.ToString()) is installed"
    } else {
        Write-Output " [x] Failed to install $moduleName!"
    }
}


# Report any modules that were installed
# --------------------------------------
Write-Output "`nNewly installed modules:"
$installedModules = Invoke-Command -ScriptBlock { Get-Module -ListAvailable | Where-Object { $_.Name -NotIn $existingModuleNames } }
foreach ($module in $installedModules) {
    Write-Output " ... $($module.Name)"
}
