Import-Module $PSScriptRoot/common/Logging -ErrorAction Stop

# Requirements
$PowershellVersionRequired = "7.0.0"
$ModuleVersionRequired = @{
    "Az" = ("ge", "5.0.0");
    "Az.Storage" = ("eq", "2.5.2");
    "AzureAD.Standard.Preview" = ("ge", "0.1.599.7")
}

# Powershell version
$PowershellVersion = (Get-Host | Select-Object Version).Version
if ($PowershellVersion -ge $PowershellVersionRequired) {
    Add-LogMessage -Level Success "Powershell version: $PowershellVersion"
} else {
    Add-LogMessage -Level Fatal "Please update your Powershell version to $PowershellVersionRequired or greater (currently using $PowershellVersion)!"
}

# Powershell modules
foreach ($ModuleName in $ModuleVersionRequired.Keys) {
    $RequirementType, $RequiredVersion = $ModuleVersionRequired[$ModuleName]
    if ($RequirementType -eq "eq") {
        $CurrentVersion = (Get-Module $ModuleName -ListAvailable | Where-Object { $_.Version -eq $RequiredVersion } | Select-Object -First 1).Version
    } elseif ($RequirementType -eq "ge") {
        $CurrentVersion = (Get-Module $ModuleName -ListAvailable | Where-Object { $_.Version -ge $RequiredVersion } | Select-Object -First 1).Version
    } else {
        Add-LogMessage -Level Fatal "Did not recognise requirement: $ModuleName $RequirementType $RequiredVersion"
    }
    if ($CurrentVersion -ge $RequiredVersion) {
        Add-LogMessage -Level Success "$ModuleName module version: $CurrentVersion"
    } else {
        $RepositoryName = "PSGallery"
        if ($ModuleName -eq "AzureAD.Standard.Preview") {
            $RepositoryName = "'Posh Test Gallery'"
            Add-LogMessage -Level Info "Please ensure the $RepositoryName package source is registered using: Register-PackageSource -Trusted -ProviderName 'PowerShellGet' -Name '$RepositoryName -Location https://www.poshtestgallery.com/api/v2/"
        }
        Add-LogMessage -Level Info "Please update the $ModuleName module using: Install-Module -Name $ModuleName -RequiredVersion $RequiredVersion -Repository $RepositoryName"
        Add-LogMessage -Level Fatal "$ModuleName module version ($CurrentVersion) does not meet the minimum requirement: $RequiredVersion!"
    }
}
