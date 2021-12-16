# Formatter settings
# ------------------
$FileExtensions = @("*.json")
$ReferenceConfigFilePath = Join-Path -Path (Get-Item $PSScriptRoot).Parent -ChildPath "resources"
$ShmIds = Get-ChildItem -Path $ReferenceConfigFilePath | ForEach-Object { $_.Name } | Where-Object { $_ -like "shm_*" } | ForEach-Object { $_.Split("_")[1] }
$ConfigFileDetails = @(Get-ChildItem -Path $ReferenceConfigFilePath -Include $FileExtensions -Recurse | ForEach-Object { @{"FilePath" = $_.FullName; "FileName" = $_.Name; "ConfigType" = $_.Name.Split("_")[0]; "ConfigId" = $_.Name.Split("_")[1]; "ShmIds" = $ShmIds } })

BeforeAll {
    Import-Module $PSScriptRoot/../../deployment/common/Configuration -Force -ErrorAction Stop
    Import-Module $PSScriptRoot/../../deployment/common/DataStructures -Force -ErrorAction Stop
}

Describe "SHM configuration file check" {
    It "Checks that SHM config '<ConfigId>' expands to give the reference: '<FilePath>'" -TestCases ($ConfigFileDetails | Where-Object { $_.ConfigType -eq "shm" }) {
        param ($FileName, $FilePath, $ConfigType, $ConfigId)

        # Load reference config and convert it to a sorted hashtable
        $referenceConfig = Get-Content -Path $FilePath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable | ConvertTo-SortedHashtable

        # Load test config
        Mock Write-Information {} # we mock Write-Information here as we expect output from the `Get-SreConfig` call
        $testConfig = Get-ShmConfig -shmId $ConfigId

        # Compare the two configs as JSON strings
        # Note that we could use `Test-Equality` from the `Functional` module here, but that would not tell us *where* any differences are
        $Diff = Compare-Object -ReferenceObject $($referenceConfig | ConvertTo-Json -Depth 10).Split("`n") -DifferenceObject $($testConfig | ConvertTo-Json -Depth 10).Split("`n")
        $Diff | Out-String | Should -BeNullOrEmpty
    }
}

Describe "SRE configuration file check" {
    BeforeAll {
    }
    It "Checks that SRE config '<ConfigId>' expands to give the reference: '<FilePath>'" -TestCases ($ConfigFileDetails | Where-Object { $_.ConfigType -eq "sre" }) {
        param ($FileName, $FilePath, $ConfigType, $ConfigId, $ShmIds)

        # Load reference config and convert it to a sorted hashtable
        $referenceConfig = Get-Content -Path $FilePath -Raw -ErrorAction Stop | ConvertFrom-Json -AsHashtable | ConvertTo-SortedHashtable

        # Split the ConfigId into shmId and sreId by matching to the list of known shmIds
        $shmId = $ShmIds | Where-Object { $ConfigId.Split($_)[0] -ne $ConfigId } | Select-Object -First 1
        $sreId = $ConfigId.Split($shmId)[1]
        # Load test config
        Mock Write-Information {} # we mock Write-Information here as we expect output from the `Get-SreConfig` call
        $testConfig = Get-SreConfig -shmId $shmId -sreId $sreId

        # Compare the two configs as JSON strings
        # Note that we could use `Test-Equality` from the `Functional` module here, but that would not tell us *where* any differences are
        $Diff = Compare-Object -ReferenceObject $($referenceConfig | ConvertTo-Json -Depth 10).Split("`n") -DifferenceObject $($testConfig | ConvertTo-Json -Depth 10).Split("`n")
        $Diff | Out-String | Should -BeNullOrEmpty
    }
}
