configuration CreateADBDC {
    Param (
        # Get deployment details
        [Parameter(Mandatory)]
        [String]$DNSServer,
        [Parameter(Mandatory)]
        [String]$DomainName,

        # Credentials
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$Admincreds,
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCredential]$SafeModeAdminCreds,


        [Int]$RetryCount = 500,
        [Int]$RetryIntervalSec = 3
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration, xStorage, xNetworking, xActiveDirectory, xPendingReboot
    $Interface = Get-NetAdapter | Where-Object { $_.Name -Like "Ethernet*" } | Select-Object -First 1
    [System.Management.Automation.PSCredential]$DomainCreds = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($Admincreds.UserName)", $Admincreds.Password)
    $features = @("AD-Domain-Services", "RSAT-ADDS-Tools", "RSAT-AD-AdminCenter")

    Node localhost {
        LocalConfigurationManager {
            ActionAfterReboot = 'ContinueConfiguration'
            ConfigurationMode = 'ApplyOnly'
            RebootNodeIfNeeded = $true
        }

        xWaitforDisk Disk2 {
            DiskNumber       = 2
            RetryIntervalSec = $RetryIntervalSec
            RetryCount       = $RetryCount
        }

        xDisk ADDataDisk {
            DiskNumber  = 2
            DriveLetter = "F"
            DependsOn   = "[xWaitForDisk]Disk2"
        }

        WindowsFeatureSet Prereqs {
            Name                 = $features
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
            DomainUserCredential = $DomainCreds
            RetryCount           = $RetryCount
            RetryIntervalSec     = $RetryIntervalSec
            DependsOn            = "[WindowsFeatureSet]Prereqs"
        }

        xADDomainController BDC {
            DomainName                    = $DomainName
            DomainAdministratorCredential = $DomainCreds
            SafemodeAdministratorPassword = $SafeModeAdminCreds
            DatabasePath                  = "F:\NTDS"
            LogPath                       = "F:\NTDS"
            SysvolPath                    = "F:\SYSVOL"
            DependsOn                     = "[xWaitForADDomain]DscForestWait"
        }

        xPendingReboot RebootAfterPromotion {
            Name      = "RebootAfterDCPromotion"
            DependsOn = "[xADDomainController]BDC"
        }
    }
}