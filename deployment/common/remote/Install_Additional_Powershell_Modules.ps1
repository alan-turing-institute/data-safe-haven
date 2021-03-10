# Don't make parameters mandatory as if there is any issue binding them, the script will prompt for them
# and remote execution will stall waiting for the non-present user to enter the missing parameter on the
# command line. This take up to 90 minutes to timeout, though you can try running resetState.cmd in
# C:\Packages\Plugins\Microsoft.CPlat.Core.RunCommandWindows\1.1.0 on the remote VM to cancel a stalled
# job, but this does not seem to have an immediate effect
# For details, see https://docs.microsoft.com/en-gb/azure/virtual-machines/windows/run-command
param(
    [Parameter(Mandatory = $false, HelpMessage = "Base-64 encoding Powershell modules to install")]
    [string]$ModuleNamesB64 = $null
)


# Deserialise Base-64 encoded variables
# -------------------------------------
$moduleNames = @()
if ($ModuleNamesB64) {
    $moduleNames = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ModuleNamesB64)) | ConvertFrom-Json
}


# Get existing modules
# --------------------
$existingModuleNames = Get-Module -ListAvailable | ForEach-Object { $_.Name }


# Install additional modules
# --------------------------
foreach ($moduleName in $moduleNames) {
    Write-Output "Installing $moduleName..."
    Install-Module -Name $moduleName -AllowClobber -Force -AcceptLicense 2>&1 3>&1 | Out-Null
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
