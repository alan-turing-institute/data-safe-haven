# Get list of packages
$packages = Get-ChildItem "C:\Installation\"
Write-Host "Preparing to install $($packages.Count) packages..."

# Install each package
foreach ($package in $packages){
    Write-Host " [ ] installing $($package.FullName)..."

    if($package -like "*.msi") {
        Write-Host "is msi"
        Start-Process $package.FullName -ArgumentList '/quiet' -Verbose -Wait
    } else {
        if($package -like "*WinSCP*exe") {
            Write-Host "is WinSCP"
            Start-Process $package.FullName -ArgumentList '/SILENT' -Verbose -Wait
        }
    }
    # Check installation status
    if ($?) {
        Write-Host " [o] Succeeded"
    } else {
        Write-Host " [x] Failed!"
    }
}