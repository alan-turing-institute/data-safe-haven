configuration CreateSecondaryDomainController {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$AdministratorCredentials,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$DNSServer,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [String]$DomainName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$SafeModeCredentials
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName xDnsServer
    Import-DscResource -ModuleName xNetworking
    Import-DscResource -ModuleName xPendingReboot
    Import-DscResource -ModuleName xStorage

    # Construct variables for use in DSC modules
    $Interface = Get-NetAdapter | Where-Object { $_.Name -Like "Ethernet*" } | Select-Object -First 1
    [System.Management.Automation.PSCredential]$DomainAdministratorCredentials = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($AdministratorCredentials.UserName)", $AdministratorCredentials.Password)
    $RequiredFeatures = @("AD-Domain-Services", "RSAT-ADDS-Tools", "RSAT-AD-AdminCenter")

    Node localhost {
        LocalConfigurationManager {
            ActionAfterReboot = "ContinueConfiguration"
            ConfigurationMode = "ApplyOnly"
            RebootNodeIfNeeded = $true
        }

        WindowsFeatureSet Prereqs {
            Name                 = $RequiredFeatures
            Ensure               = "Present"
            IncludeAllSubFeature = $true
        }

        xDnsServerAddress DnsServerAddress {
            Address        = $DNSServer
            InterfaceAlias = $Interface.Name
            AddressFamily  = "IPv4"
            DependsOn      = "[WindowsFeatureSet]Prereqs"
        }

        xWaitForADDomain DscForestWait {
            DomainName           = $DomainName
            DomainUserCredential = $DomainAdministratorCredentials
            RetryCount           = 500
            RetryIntervalSec     = 3
            DependsOn            = "[WindowsFeatureSet]Prereqs"
        }

        xADDomainController SecondaryDC {
            DomainName                    = $DomainName
            DomainAdministratorCredential = $DomainAdministratorCredentials
            SafemodeAdministratorPassword = $SafeModeCredentials
            DatabasePath                  = "C:\ActiveDirectory\NTDS"
            LogPath                       = "C:\ActiveDirectory\NTDS"
            SysvolPath                    = "C:\ActiveDirectory\SYSVOL"
            DependsOn                     = "[xWaitForADDomain]DscForestWait"
        }

        xPendingReboot RebootAfterPromotion {
            Name      = "RebootAfterDCPromotion"
            DependsOn = "[xADDomainController]SecondaryDC"
        }
    }
}
