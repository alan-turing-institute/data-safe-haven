Import-Module $PSScriptRoot/common/Logging -Force -ErrorAction Stop

# Requirements
$PowershellVersionRequired = "7.0.0"
$ModuleVersionRequired = @{
    "Az.Accounts"            = @("ge", "2.9.0")
    "Az.Automation"          = @("ge", "1.7.3")
    "Az.Compute"             = @("ge", "4.29.0")
    "Az.DataProtection"      = @("ge", "0.4.0")
    "Az.Dns"                 = @("ge", "1.1.2")
    "Az.KeyVault"            = @("ge", "4.6.0")
    "Az.Monitor"             = @("ge", "3.0.1")
    "Az.MonitoringSolutions" = @("ge", "0.1.0")
    "Az.Network"             = @("ge", "4.18.0")
    "Az.OperationalInsights" = @("ge", "3.1.0")
    "Az.PrivateDns"          = @("ge", "1.0.3")
    "Az.RecoveryServices"    = @("ge", "5.4.1")
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
        Install-Module -Name $ModuleName -RequiredVersion $RequiredVersion -Repository $RepositoryName
    }
}
