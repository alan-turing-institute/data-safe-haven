param (
  [Parameter(Mandatory = $false, HelpMessage = "If this is set, install any missing modules, otherwise warn.")]
  [switch]$InstallMissing,
  [Parameter(Mandatory = $false, HelpMessage = "If this is set, install any dev modules, otherwise ignore them.")]
  [switch]$IncludeDev
)

Import-Module $PSScriptRoot/common/Logging -Force -ErrorAction Stop

# Requirements
$PowershellMinVersion = "7.0.0"
$PowershellMaxVersion = "7.2.7"
$ModuleVersionRequired = @{
    "Az.Accounts"                                  = @("ge", "2.9.0")
    "Az.Automation"                                = @("ge", "1.7.3")
    "Az.Compute"                                   = @("ge", "4.29.0")
    "Az.DataProtection"                            = @("ge", "0.4.0")
    "Az.Dns"                                       = @("ge", "1.1.2")
    "Az.KeyVault"                                  = @("ge", "4.6.0")
    "Az.Monitor"                                   = @("ge", "3.0.1")
    "Az.MonitoringSolutions"                       = @("ge", "0.1.0")
    "Az.Network"                                   = @("ge", "4.18.0")
    "Az.OperationalInsights"                       = @("ge", "3.1.0")
    "Az.PrivateDns"                                = @("ge", "1.0.3")
    "Az.RecoveryServices"                          = @("ge", "5.4.1")
    "Az.Resources"                                 = @("ge", "6.0.1")
    "Az.Storage"                                   = @("ge", "4.7.0")
    "Microsoft.Graph.Authentication"               = @("ge", "1.10.0")
    "Microsoft.Graph.Applications"                 = @("ge", "1.10.0")
    "Microsoft.Graph.Identity.DirectoryManagement" = @("ge", "1.10.0")
    "Poshstache"                                   = @("ge", "0.1.10")
    "Powershell-Yaml"                              = @("ge", "0.4.2")
}
if ($IncludeDev.IsPresent) {
    $ModuleVersionRequired["Pester"] = ("ge", "5.1.0")
    $ModuleVersionRequired["PSScriptAnalyzer"] = ("ge", "1.19.0")
}

# Powershell version
$PowershellVersion = (Get-Host | Select-Object Version).Version
if ($PowershellVersion -gt $PowershellMaxVersion) {
    Add-LogMessage -Level Fatal "Please downgrade Powershell to a minimum version of $PowershellMinVersion and a maximum of $PowershellMaxVersion (currently using $PowershellVersion)!"
} elseif ($PowershellVersion -lt $PowershellMinVersion) {
    Add-LogMessage -Level Fatal "Please upgrade Powershell to a minimum version of $PowershellMinVersion and a maximum of $PowershellMaxVersion (currently using $PowershellVersion)!"
} else {
    Add-LogMessage -Level Success "Powershell version: $PowershellVersion"
}

# Powershell modules
$RepositoryName = "PSGallery"
foreach ($ModuleName in $ModuleVersionRequired.Keys) {
    $RequirementType, $RequiredVersion = $ModuleVersionRequired[$ModuleName]
    if ($RequirementType -eq "eq") {
        $CurrentVersion = (Get-Module $ModuleName -ListAvailable | Where-Object { $_.Version -eq $RequiredVersion } | Select-Object -First 1).Version
    } elseif ($RequirementType -eq "ge") {
        $CurrentVersion = (Get-Module $ModuleName -ListAvailable | Where-Object { $_.Version -ge $RequiredVersion } | Select-Object -First 1).Version
    } else {
        Add-LogMessage -Level Fatal "Did not recognise requirement: '$ModuleName $RequirementType $RequiredVersion'"
    }
    if ($CurrentVersion -ge $RequiredVersion) {
        Add-LogMessage -Level Success "$ModuleName module version: $CurrentVersion"
    } elseif ($InstallMissing.IsPresent) {
        Add-LogMessage -Level Info "Installing $ModuleName module version: $RequiredVersion..."
        Install-Module -Name $ModuleName -RequiredVersion $RequiredVersion -Repository $RepositoryName -Scope CurrentUser
    } else {
        Add-LogMessage -Level Warning "$ModuleName module version ($CurrentVersion) does not meet the minimum requirement: $RequiredVersion!"
        Add-LogMessage -Level Info "Please update the $ModuleName module using: Install-Module -Name $ModuleName -RequiredVersion $RequiredVersion -Repository $RepositoryName"
    }
}
