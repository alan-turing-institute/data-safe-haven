# Install PowerShellGet
Write-Host "Installing PowerShellGet..."
Install-Module -Name PowerShellGet -Force
if ($?) {
    Write-Host " [o] Succeeded"
} else {
    Write-Host " [x] Failed!"
}
