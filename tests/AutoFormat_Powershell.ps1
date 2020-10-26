Import-Module PSScriptAnalyzer -ErrorAction Stop
Import-Module $PSScriptRoot/../deployment/common/Logging -ErrorAction Stop


# Formatter settings
# ------------------
$FileExtensions = @("*.ps1", "*.psm1")
$ExcludePaths = @("*/CreateADPDC/*", "*/CreateADBDC/*") # do not reformat the Windows DSC files as they are fragile
$CodeRootPath = Join-Path -Path (Get-Item $PSScriptRoot).Parent -ChildPath "deployment"
$SettingsPath = Join-Path -Path (Get-Item $PSScriptRoot).Parent -ChildPath ".PSScriptFormatterSettings.psd1"
$PowershellFilePaths = @(Get-ChildItem -Path $CodeRootPath -Include $FileExtensions -Recurse | Where-Object { $(foreach ($ExcludePath in $ExcludePaths) { $_.FullName -notlike $ExcludePath }) -notcontains $false } | Select-Object -ExpandProperty FullName)


# Run Invoke-Formatter on all files
# ---------------------------------
foreach ($PowershellFilePath in $PowershellFilePaths) {
    $Unformatted = Get-Content -Path $PowershellFilePath -Raw

    # Strip empty lines
    $LineEndingMarker = $Unformatted -match "\r\n$" ? "`r`n" : "`n"
    $Formatted = $Unformatted -replace "(?s)$LineEndingMarker\s*$"

    # Call formatter
    $Formatted = Invoke-Formatter -ScriptDefinition $Formatted -Settings $SettingsPath

    # Write to output if the text differs - note that this does not consider trailing blank lines which are added by Out-File
    if ($Formatted -ne $Unformatted) {
        $Formatted | Out-File $PowershellFilePath -Encoding "UTF8NoBOM"
        $Formatted = Get-Content -Path $PowershellFilePath -Raw
    }

    # Check whether any changes were made to the file
    if ($Formatted -ne $Unformatted) {
        Add-LogMessage -Level Info "Formatting ${PowershellFilePath}..."
    } else {
        Add-LogMessage -Level Info "${PowershellFilePath} is already formatted"
    }
}
