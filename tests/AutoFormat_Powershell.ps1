param(
    [Parameter(Mandatory = $false, HelpMessage = "Restrict to only run over files in the given path")]
    [string]$TargetPath,
    [Parameter(Mandatory = $false, HelpMessage = "Only alter line endings and file encodings")]
    [switch]$EncodingOnly
)

Import-Module PSScriptAnalyzer -ErrorAction Stop
Import-Module $PSScriptRoot/../deployment/common/Logging -ErrorAction Stop


# Set the root path which we will format
# --------------------------------------
$CodeRootPath = $TargetPath ? $TargetPath : (Join-Path -Path (Get-Item $PSScriptRoot).Parent -ChildPath "deployment")


# Formatter settings
# ------------------
$FileExtensions = @("*.ps1", "*.psm1", "*.psd1")
$SettingsPath = Join-Path -Path (Get-Item $PSScriptRoot).Parent -ChildPath ".PSScriptFormatterSettings.psd1"
$PowershellFilePaths = @(Get-ChildItem -Path $CodeRootPath -Include $FileExtensions -Recurse | Select-Object -ExpandProperty FullName)


# Run Invoke-Formatter on all files
# ---------------------------------
foreach ($PowershellFilePath in $PowershellFilePaths) {
    $Unformatted = Get-Content -Path $PowershellFilePath -Raw


    # Detect the end-of-line marker and strip empty lines
    # ---------------------------------------------------
    $EOLMarker = $Unformatted -match "\r\n$" ? "`r`n" : "`n"
    $Formatted = $Unformatted -replace "(?s)$EOLMarker\s*$"


    # Call formatter
    # --------------
    if (-not $EncodingOnly) {
        $Formatted = Invoke-Formatter -ScriptDefinition $Formatted -Settings $SettingsPath
    }


    # Set correct line endings and correct encoding.
    # Omitting the Byte Order Mark gives better cross-platform compatibility but Windows scripts need it
    # We use Set-Content instead of Out-File so that we can write line-endings that are not the platform default
    # ----------------------------------------------------------------------------------------------------------
    $Encoding = $EOLMarker -eq "`r`n" ? "UTF8BOM" : "UTF8NoBOM"
    $Formatted.Replace("`r`n", "`r`r").Replace("`n", "`r`r").Replace("`r`r", $EOLMarker) | Set-Content -Path $PowershellFilePath -Encoding $Encoding


    # Check whether any changes were made to the file
    # -----------------------------------------------
    $Formatted = Get-Content -Path $PowershellFilePath -Raw
    if ($Formatted -ne $Unformatted) {
        Add-LogMessage -Level Info "Formatting ${PowershellFilePath}..."
    } else {
        Add-LogMessage -Level Info "${PowershellFilePath} is already formatted"
    }
}
