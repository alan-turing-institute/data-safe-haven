Import-Module PSScriptAnalyzer


# Formatter settings
# ------------------
$FileExtensions = @("*.ps1", "*.psm1", "*.psd1")
$CodeDirectories = @("deployment", "tests")
$FileDetails = @()
foreach ($CodeDirectory in $CodeDirectories) {
    $CodeDirectoryPath = Join-Path -Path (Get-Item $PSScriptRoot).Parent.Parent -ChildPath $CodeDirectory
    $FileDetails += @(Get-ChildItem -Path $CodeDirectoryPath -Include $FileExtensions -Recurse | Where-Object { ($_.FullName -notmatch "shm-dc1-setup-scripts") -and ($_ -notmatch "shm-dc2-setup-scripts") } | ForEach-Object { @{"FilePath" = $_.FullName; "FileName" = $_.Name } })
}


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
