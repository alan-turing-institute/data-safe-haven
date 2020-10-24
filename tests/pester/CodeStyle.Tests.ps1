Import-Module PSScriptAnalyzer


# Formatter settings
# ------------------
$FileExtensions = "*.ps1", "*.psm1"
$RootPath = Join-Path -Path $PSScriptRoot -ChildPath ".." ".." "deployment"
$SettingsPath = Join-Path -Path $PSScriptRoot -ChildPath ".." ".." ".PSScriptFormatterSettings.psd1"
$FileDetails = @(Get-ChildItem -Path $RootPath -Include $FileExtensions -Recurse | `
                 Select-Object -ExpandProperty FullName | `
                 ForEach-Object { @{"FilePath" = $_; "FileName" = $(Split-Path $_ -Leaf) } })


# Run Invoke-Formatter on all files
# ---------------------------------
Describe "Powershell formatting" {
    It "Checks that '<FileName>' is correctly formatted" -TestCases $FileDetails {
        param ($FileName, $FilePath)
        $Formatted = Invoke-Formatter -ScriptDefinition $(Get-Content -Path $FilePath -Raw) -Settings $SettingsPath
        $FilePath | Should -FileContentMatchExactly $Formatted
    }
}
