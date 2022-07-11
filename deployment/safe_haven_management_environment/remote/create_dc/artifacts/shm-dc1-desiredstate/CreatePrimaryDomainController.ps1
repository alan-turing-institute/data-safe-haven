configuration CreatePrimaryDomainController {
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$AdministratorCredentials,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$DomainName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [String]$DomainNetBIOSName,

        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$SafeModeCredentials
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName xActiveDirectory
    Import-DscResource -ModuleName xNetworking
    Import-DscResource -ModuleName xPendingReboot
    Import-DscResource -ModuleName xStorage

    # Construct variables for use in DSC modules
    $Interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1
    [System.Management.Automation.PSCredential]$DomainAdministratorCredentials = New-Object System.Management.Automation.PSCredential ("${DomainName}\$($AdministratorCredentials.UserName)", $AdministratorCredentials.Password)
    $BlobSasToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($BlobSasTokenB64))
    $BlobNames = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($BlobNamesB64)) | ConvertFrom-Json

    Node localhost {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ConfigurationMode  = "ApplyOnly"
        }

        WindowsFeature DNS {
            Ensure = "Present"
            Name   = "DNS"
        }

        Script EnableDNSDiags {
            SetScript  = {
                Write-Verbose -Verbose "Enabling DNS client diagnostics"
                Set-DnsServerDiagnostics -All $true
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn  = "[WindowsFeature]DNS"
        }

        WindowsFeature DnsTools {
            Ensure    = "Present"
            Name      = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
        }

        xDnsServerAddress DnsServerAddress {
            Address        = "127.0.0.1"
            InterfaceAlias = $Interface.Name
            AddressFamily  = "IPv4"
            DependsOn      = "[WindowsFeature]DNS"
        }

        WindowsFeature ADDSInstall {
            Ensure     = "Present"
            Name       = "AD-Domain-Services"
            DependsOn  = "[WindowsFeature]DNS"
        }

        WindowsFeature ADDSTools {
            Ensure     = "Present"
            Name       = "RSAT-ADDS-Tools"
            DependsOn  = "[WindowsFeature]ADDSInstall"
        }

        WindowsFeature ADAdminCenter {
            Ensure    = "Present"
            Name      = "RSAT-AD-AdminCenter"
            DependsOn = "[WindowsFeature]ADDSTools"
        }

        xADDomain PrimaryDS {
            DomainName                    = $DomainName
            DomainNetBIOSName             = $DomainNetBIOSName
            DomainAdministratorCredential = $DomainAdministratorCredentials
            SafemodeAdministratorPassword = $SafeModeCredentials
            DatabasePath                  = "C:\ActiveDirectory\NTDS"
            LogPath                       = "C:\ActiveDirectory\NTDS"
            SysvolPath                    = "C:\ActiveDirectory\SYSVOL"
            DependsOn                     = "[WindowsFeature]ADDSInstall"
        }

        xPendingReboot RebootAfterPromotion {
            Name      = "RebootAfterPromotion"
            DependsOn = "[xADDomain]PrimaryDS"
        }
    }
}

