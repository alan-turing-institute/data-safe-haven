Import-Module $PSScriptRoot/../../deployment/common/Configuration -Force -ErrorAction Stop


# Formatter settings
# ------------------
$FileExtensions = @("*.json")
$ReferenceConfigFilePath = Join-Path -Path (Get-Item $PSScriptRoot).Parent -ChildPath "resources"
$ConfigFileDetails = @(Get-ChildItem -Path $ReferenceConfigFilePath -Include $FileExtensions -Recurse | ForEach-Object { @{"FilePath" = $_.FullName; "FileName" = $_.Name; "ConfigType" = $_.Name.Split("_")[0]; "ConfigId" = $_.Name.Split("_")[1] } })

Describe "SHM configuration file check" {
    It "Checks that SHM config '<ConfigId>' expands to give the reference: '<FilePath>'" -TestCases ($ConfigFileDetails | Where-Object { $_.ConfigType -eq "shm" }) {
        param ($FileName, $FilePath, $ConfigType, $ConfigId)

        # Load reference config and convert it to a sorted hashtable
        $referenceConfig = Get-Content -Path $FilePath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable | ConvertTo-SortedHashtable

        # Load test config
        Mock Write-Host {} # we mock Write-Host here as we expect output from the `Get-SreConfig` call
        $testConfig = Get-ShmConfig -shmId $configId

        # Compare the two configs as JSON strings
        # Note that we could use `Test-Equality` from the `Functional` module here, but that would not tell us *where* any differences are
        $Diff = Compare-Object -ReferenceObject $($referenceConfig | ConvertTo-Json -Depth 10).Split("`n") -DifferenceObject $($testConfig | ConvertTo-Json -Depth 10).Split("`n")
        $Diff | Out-String | Should -BeNullOrEmpty
    }
}

Describe "SRE configuration file check" {
    It "Checks that SRE config '<ConfigId>' expands to give the reference: '<FilePath>'" -TestCases ($ConfigFileDetails | Where-Object { $_.ConfigType -eq "sre" }) {
        param ($FileName, $FilePath, $ConfigType, $ConfigId)

        # Load reference config and convert it to a sorted hashtable
        $referenceConfig = Get-Content -Path $FilePath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable | ConvertTo-SortedHashtable

        # Get the shmId from ConfigId, given that all test configs have sreId "sandbox"
        $sreId = "sandbox"
        $shmId = $ConfigId.Split($sreId)[0]
        # Load test config
        Mock Write-Host {} # we mock Write-Host here as we expect output from the `Get-SreConfig` call
        $testConfig = Get-SreConfig -shmId $shmId -sreId $sreId

        # Compare the two configs as JSON strings
        # Note that we could use `Test-Equality` from the `Functional` module here, but that would not tell us *where* any differences are
        $Diff = Compare-Object -ReferenceObject $($referenceConfig | ConvertTo-Json -Depth 10).Split("`n") -DifferenceObject $($testConfig | ConvertTo-Json -Depth 10).Split("`n")
        $Diff | Out-String | Should -BeNullOrEmpty
    }
}
