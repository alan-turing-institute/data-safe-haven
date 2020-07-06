# Get list of packages
$packages = Get-ChildItem "C:\Installation\"
Write-Output "Preparing to install $($packages.Count) packages..."

# Install each package
foreach ($package in $packages) {
    Write-Output " [ ] installing $($package.FullName)..."

    if ($package -like "*.msi") {
        Start-Process $package.FullName -ArgumentList '/quiet' -Verbose -Wait
    }
    # Check installation status
    if ($?) {
        Write-Output " [o] Succeeded"
    } else {
        Write-Output " [x] Failed!"
    }
}