Import-Module PSScriptAnalyzer


# Formatter settings
# ------------------
$FileExtensions = @("*.ps1", "*.psm1")
$ExcludePaths = @("*/CreateADPDC/*", "*/CreateADBDC/*") # do not reformat the Windows DSC files as they are fragile
$CodeRootPath = Join-Path -Path (Get-Item $PSScriptRoot).Parent.Parent -ChildPath "deployment"
$FileDetails = @(Get-ChildItem -Path $CodeRootPath -Include $FileExtensions -Recurse | Where-Object { $(foreach ($ExcludePath in $ExcludePaths) { $_.FullName -notlike $ExcludePath }) -notcontains $false } | ForEach-Object { @{"FilePath" = $_.FullName; "FileName" = $_.Name } })


# Run Invoke-Formatter on all files
# ---------------------------------
Describe "Powershell formatting" {
    BeforeAll {
        $SettingsPath = Join-Path -Path (Get-Item $PSScriptRoot).Parent.Parent -ChildPath ".PSScriptFormatterSettings.psd1"
    }
    It "Checks that '<FilePath>' is correctly formatted" -TestCases $FileDetails {
        param ($FileName, $FilePath)
        $Unformatted = Get-Content -Path $FilePath -Raw
        $Formatted = Invoke-Formatter -ScriptDefinition $Unformatted -Settings $SettingsPath
        $Diff = Compare-Object -ReferenceObject $Unformatted.Split("`n") -DifferenceObject $Formatted.Split("`n")
        $Diff | Out-String | Should -BeNullOrEmpty
    }
}
