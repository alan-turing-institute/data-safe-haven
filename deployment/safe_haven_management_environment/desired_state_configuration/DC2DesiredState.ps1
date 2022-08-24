configuration InstallPowershellModules {
    Import-DscResource -ModuleName PowerShellModule

    Node localhost {
        PSModuleResource MSOnline {
            Ensure = "present"
            Module_Name = "MSOnline"
        }

        PSModuleResource PackageManagement {
            Ensure = "present"
            Module_Name = "PackageManagement"
        }

        PSModuleResource PowerShellGet {
            Ensure = "present"
            Module_Name = "PowerShellGet"
        }

        PSModuleResource PSWindowsUpdate {
            Ensure = "present"
            Module_Name = "PSWindowsUpdate"
        }
    }
}


configuration CreateSecondaryDomainController {
    param (
        [Parameter(HelpMessage = "Path to Active Directory log volume")]
        [ValidateNotNullOrEmpty()]
        [string]$ActiveDirectoryLogPath,

        [Parameter(HelpMessage = "Path to Active Directory NTDS volume")]
        [ValidateNotNullOrEmpty()]
        [string]$ActiveDirectoryNtdsPath,

        [Parameter(HelpMessage = "Path to Active Directory system volume")]
        [ValidateNotNullOrEmpty()]
        [string]$ActiveDirectorySysvolPath,

        [Parameter(Mandatory = $true, HelpMessage = "Domain administrator credentials")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$DomainAdministratorCredentials,

        [Parameter(Mandatory = $true, HelpMessage = "FQDN for the SHM domain")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainFqdn,

        [Parameter(Mandatory, HelpMessage = "Private IP address of primary domain controller")]
        [ValidateNotNullOrEmpty()]
        [String]$PrimaryDomainControllerIp,

        [Parameter(Mandatory = $true, HelpMessage = "VM administrator safe mode credentials")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$SafeModeCredentials
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName ComputerManagementDsc
    Import-DscResource -ModuleName NetworkingDsc

    # Construct variables for use in DSC modules
    $Interface = Get-NetAdapter | Where-Object { $_.Name -Like "Ethernet*" } | Select-Object -First 1

    Node localhost {
        LocalConfigurationManager {
            ActionAfterReboot = "ContinueConfiguration"
            ConfigurationMode = "ApplyOnly"
            RebootNodeIfNeeded = $true
        }

        WindowsFeature ADDomainServices {
            Ensure = "Present"
            Name = "AD-Domain-Services"
        }

        WindowsFeature ADDSTools {
            Ensure = "Present"
            Name = "RSAT-ADDS-Tools"
        }

        WindowsFeature ADAdminCenter {
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter"
        }

        WindowsFeature ADPowerShell {
            Ensure = "Present"
            Name = "RSAT-AD-PowerShell"
        }

        DnsServerAddress DnsServerAddress { # from NetworkingDsc
            Address = $PrimaryDomainControllerIp
            AddressFamily = "IPv4"
            InterfaceAlias = $Interface.Name
        }

        WaitForADDomain WaitForestAvailability { # from ActiveDirectoryDsc
            Credential = $DomainAdministratorCredentials
            DomainName = $DomainFqdn
            DependsOn = @("[WindowsFeature]ADPowerShell", "[WindowsFeature]ADDomainServices", "[DnsServerAddress]DnsServerAddress")
        }

        ADDomainController SecondaryDomainController { # from ActiveDirectoryDsc
            Credential = $DomainAdministratorCredentials
            DatabasePath = $ActiveDirectoryNtdsPath
            DomainName = $DomainFqdn
            LogPath = $ActiveDirectoryLogPath
            SafeModeAdministratorPassword = $SafeModeCredentials
            SysvolPath = $ActiveDirectorySysvolPath
            DependsOn = "[WaitForADDomain]WaitForestAvailability"
        }

        WindowsFeature DNS { # Promotion to SecondaryDomainController should have already enabled this but we ensure it here
            Ensure = "Present"
            Name = "DNS"
            DependsOn = "[ADDomainController]SecondaryDomainController"
        }

        WindowsFeature DnsServer { # Promotion to SecondaryDomainController should have already enabled this but we ensure it here
            Ensure = "Present"
            Name = "RSAT-DNS-Server"
            DependsOn = "[WindowsFeature]DNS"
        }

        PendingReboot RebootAfterPromotion { # from ComputerManagementDsc
            Name = "RebootAfterDCPromotion"
            DependsOn = "[WindowsFeature]DnsServer"
        }
    }
}


configuration ConfigureSecondaryDomainController {
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Active Directory base path")]
        [ValidateNotNullOrEmpty()]
        [string]$ActiveDirectoryBasePath,

        [Parameter(Mandatory = $true, HelpMessage = "VM administrator credentials")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$AdministratorCredentials,

        [Parameter(Mandatory = $true, HelpMessage = "FQDN for the SHM domain")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainFqdn,

        [Parameter(Mandatory, HelpMessage = "Private IP address of primary domain controller")]
        [ValidateNotNullOrEmpty()]
        [String]$PrimaryDomainControllerIp,

        [Parameter(Mandatory = $true, HelpMessage = "VM administrator safe mode credentials")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$SafeModeCredentials
    )

    # Construct variables for passing to DSC configurations
    $activeDirectoryLogPath = Join-Path $ActiveDirectoryBasePath "Logs"
    $activeDirectoryNtdsPath = Join-Path $ActiveDirectoryBasePath "NTDS"
    $activeDirectorySysvolPath = Join-Path $ActiveDirectoryBasePath "SYSVOL"
    $domainAdministratorCredentials = New-Object System.Management.Automation.PSCredential ("${DomainFqdn}\$($AdministratorCredentials.UserName)", $AdministratorCredentials.Password)

    Node localhost {
        InstallPowershellModules InstallPowershellModules {}

        CreateSecondaryDomainController CreateSecondaryDomainController {
            ActiveDirectoryLogPath = $activeDirectoryLogPath
            ActiveDirectoryNtdsPath = $activeDirectoryNtdsPath
            ActiveDirectorySysvolPath = $activeDirectorySysvolPath
            DomainAdministratorCredentials = $domainAdministratorCredentials
            DomainFqdn = $DomainFqdn
            PrimaryDomainControllerIp = $PrimaryDomainControllerIp
            SafeModeCredentials = $SafeModeCredentials
        }
    }
}
