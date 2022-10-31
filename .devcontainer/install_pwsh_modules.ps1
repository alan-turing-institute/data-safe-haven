# Requirements
$ModuleVersionRequired = @{
    "Az.Accounts"                    = @("ge", "2.9.0")
    "Az.Automation"                  = @("ge", "1.7.3")
    "Az.Compute"                     = @("ge", "4.29.0")
    "Az.DataProtection"              = @("ge", "0.4.0")
    "Az.Dns"                         = @("ge", "1.1.2")
    "Az.KeyVault"                    = @("ge", "4.6.0")
    "Az.Monitor"                     = @("ge", "3.0.1")
    "Az.MonitoringSolutions"         = @("ge", "0.1.0")
    "Az.Network"                     = @("ge", "4.18.0")
    "Az.OperationalInsights"         = @("ge", "3.1.0")
    "Az.PrivateDns"                  = @("ge", "1.0.3")
    "Az.RecoveryServices"            = @("ge", "5.4.1")
    "Az.Resources"                   = @("ge", "6.0.1")
    "Az.Storage"                     = @("ge", "4.7.0")
    "Microsoft.Graph.Authentication" = @("ge", "1.5.0")
    "Microsoft.Graph.Applications"   = @("ge", "1.5.0")
    "Microsoft.Graph.Identity.DirectoryManagement" = @("ge", "1.10.0")
    "Poshstache"                     = @("ge", "0.1.10")
    "Powershell-Yaml"                = @("ge", "0.4.2")
}

# Powershell modules
$RepositoryName = "PSGallery"
Set-PSRepository -Name $RepositoryName -InstallationPolicy Trusted
foreach ($ModuleName in $ModuleVersionRequired.Keys) {
    Install-Module -Name $ModuleName -RequiredVersion $RequiredVersion -Repository $RepositoryName -Scope CurrentUser
}
