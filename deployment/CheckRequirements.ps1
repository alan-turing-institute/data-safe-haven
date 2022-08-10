Import-Module $PSScriptRoot/common/Logging -ErrorAction Stop

# Requirements
$PowershellVersionRequired = "7.0.0"
$ModuleVersionRequired = @{
    "Az"                     = @("ge", "6.0.0")
    "Az.DataProtection"      = @("ge", "0.4.0")
    "Az.MonitoringSolutions" = @("ge", "0.1.0")
    "Az.Resources"           = @("ge", "6.0.1")
    "Az.Storage"             = @("ge", "4.7.0")
    "Microsoft.Graph"        = @("ge", "1.5.0")
    "Poshstache"             = @("ge", "0.1.10")
    "Powershell-Yaml"        = @("ge", "0.4.2")
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
        Add-LogMessage -Level Info "Please update the $ModuleName module using: Install-Module -Name $ModuleName -RequiredVersion $RequiredVersion -Repository $RepositoryName"
        Add-LogMessage -Level Fatal "$ModuleName module version ($CurrentVersion) does not meet the minimum requirement: $RequiredVersion!"
    }
}
