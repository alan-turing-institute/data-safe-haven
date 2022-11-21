# Note that we require the following DSC modules to be installed
# - ActiveDirectoryDsc
# - PSModulesDsc
# - xPendingReboot
# - xPSDesiredStateConfiguration
# Note that logs are in C:\Windows\System32\Configuration\ConfigurationStatus

Configuration InstallPowershellModules {
    Import-DscResource -ModuleName PSModulesDsc -ModuleVersion 1.0.13.0

    Node localhost {
        PowershellModule MSOnline {
            Ensure = "Present"
            Name = "MSOnline"
            RequiredVersion = "1.1.183.66"
        }
    }
}

Configuration InstallActiveDirectory {
    param (
        [Parameter(HelpMessage = "Path to Active Directory log volume")]
        [ValidateNotNullOrEmpty()]
        [String]$IADActiveDirectoryLogPath,

        [Parameter(HelpMessage = "Path to Active Directory NTDS volume")]
        [ValidateNotNullOrEmpty()]
        [String]$IADActiveDirectoryNtdsPath,

        [Parameter(HelpMessage = "Path to Active Directory system volume")]
        [ValidateNotNullOrEmpty()]
        [String]$IADActiveDirectorySysvolPath,

        [Parameter(Mandatory = $true, HelpMessage = "Domain administrator password")]
        [ValidateNotNullOrEmpty()]
        [String]$IADDomainAdministratorPassword,

        [Parameter(Mandatory = $true, HelpMessage = "Domain administrator password")]
        [ValidateNotNullOrEmpty()]
        [String]$IADDomainAdministratorUsername,

        [Parameter(Mandatory = $true, HelpMessage = "FQDN for the SHM domain")]
        [ValidateNotNullOrEmpty()]
        [String]$IADDomainName,

        [Parameter(Mandatory = $true, HelpMessage = "NetBIOS name for the domain")]
        [ValidateNotNullOrEmpty()]
        [String]$IADDomainNetBiosName
    )

    Import-DscResource -ModuleName ActiveDirectoryDsc -ModuleVersion 6.2.0
    Import-DscResource -ModuleName xPendingReboot -ModuleVersion 0.4.0.0 # note that ComputerManagementDsc is too old to include PendingReboot

    # Construct variables for passing to DSC configurations
    $DomainAdministratorPasswordSecure = ConvertTo-SecureString -String $IADDomainAdministratorPassword -AsPlainText -Force
    $DomainAdministratorCredentials = New-Object System.Management.Automation.PSCredential ("${IADDomainName}\$($IADDomainAdministratorUsername)", $DomainAdministratorPasswordSecure)
    $SafeModeAdministratorCredentials = New-Object System.Management.Automation.PSCredential ("safemode${IADDomainAdministratorUsername}".ToLower(), $DomainAdministratorPasswordSecure)

    Node localhost {
        # Install Active Directory domain services
        WindowsFeature ADDomainServices { # built-in
            Ensure = "Present"
            Name = "AD-Domain-Services"
        }

        # Install Active Directory domain services tools
        WindowsFeature ADDSTools { # built-in
            Ensure = "Present"
            Name = "RSAT-ADDS-Tools"
        }

        # Install Active Directory admin centre
        WindowsFeature ADAdminCenter { # built-in
            Ensure = "Present"
            Name = "RSAT-AD-AdminCenter"
        }

        # Reboot
        xPendingReboot RebootBeforePromotion { # from xPendingReboot
            Name = "RebootBeforePromotion"
            SkipCcmClientSDK = $true
            DependsOn = @("[WindowsFeature]ADDomainServices", "[WindowsFeature]ADDSTools", "[WindowsFeature]ADAdminCenter")
        }

        # Create the domain
        ADDomain Domain { # from ActiveDirectoryDsc
            Credential = $DomainAdministratorCredentials
            DatabasePath = $IADActiveDirectoryNtdsPath
            DomainName = $IADDomainName
            DomainNetBiosName = $IADDomainNetBiosName
            LogPath = $IADActiveDirectoryLogPath
            SafeModeAdministratorPassword = $SafeModeAdministratorCredentials
            SysvolPath = $IADActiveDirectorySysvolPath
            DependsOn = @("[WindowsFeature]ADDomainServices", "[xPendingReboot]RebootBeforePromotion")
        }

        # Disable network-level authentication
        Registry DisableRDPNLA { # built-in
            Key = "HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations\RDP-Tcp"
            ValueName = "UserAuthentication"
            ValueData = 0
            ValueType = "Dword"
            Ensure = "Present"
            DependsOn = "[ADDomain]Domain"
        }

        # Reboot
        xPendingReboot RebootAfterPromotion { # from xPendingReboot
            Name = "RebootAfterPromotion"
            SkipCcmClientSDK = $true
            DependsOn = "[Registry]DisableRDPNLA"
        }
    }
}

Configuration ConfigureActiveDirectory {
    param (
        [Parameter(HelpMessage = "AzureAD connect password")]
        [ValidateNotNullOrEmpty()]
        [String]$CADAzureADConnectPassword,

        [Parameter(HelpMessage = "AzureAD connect user name")]
        [ValidateNotNullOrEmpty()]
        [String]$CADAzureADConnectUsername,

        [Parameter(Mandatory = $true, HelpMessage = "Domain administrator password")]
        [ValidateNotNullOrEmpty()]
        [String]$CADDomainAdministratorPassword,

        [Parameter(Mandatory = $true, HelpMessage = "Domain administrator password")]
        [ValidateNotNullOrEmpty()]
        [String]$CADDomainAdministratorUsername,

        [Parameter(Mandatory = $true, HelpMessage = "Domain computer manager password")]
        [ValidateNotNullOrEmpty()]
        [String]$CADDomainComputerManagerPassword,

        [Parameter(Mandatory = $true, HelpMessage = "Domain computer manager username")]
        [ValidateNotNullOrEmpty()]
        [String]$CADDomainComputerManagerUsername,

        [Parameter(Mandatory = $true, HelpMessage = "FQDN for the SHM domain")]
        [ValidateNotNullOrEmpty()]
        [String]$CADDomainName,

        [Parameter(Mandatory = $true, HelpMessage = "Root DN for the SHM domain")]
        [ValidateNotNullOrEmpty()]
        [String]$CADDomainRootDn,

        [Parameter(Mandatory = $true, HelpMessage = "FQDN for the SHM domain")]
        [ValidateNotNullOrEmpty()]
        [String]$CADDomainName
    )

    Import-DscResource -ModuleName ActiveDirectoryDsc -ModuleVersion 6.2.0

    # Construct variables for passing to DSC configurations
    $DomainAdministratorPasswordSecure = ConvertTo-SecureString -String $CADDomainAdministratorPassword -AsPlainText -Force
    $DomainAdministratorCredentials = New-Object System.Management.Automation.PSCredential ("${CADDomainName}\$($CADDomainAdministratorUsername)", $DomainAdministratorPasswordSecure)
    $CADDomainRootDn = "DC=$($CADDomainName.Replace('.',',DC='))"
    $DataSafeHavenUnits = @{
        DomainComputers = @{
            Description = "Data Safe Haven Domain Computers"
            Path        = "OU=Data Safe Haven Domain Computers,${CADDomainRootDn}"
        }
        ResearchUsers   = @{
            Description = "Data Safe Haven Research Users"
            Path        = "OU=Data Safe Haven Research Users,${CADDomainRootDn}"
        }
        SecurityGroups  = @{
            Description = "Data Safe Haven Security Groups"
            Path        = "OU=Data Safe Haven Security Groups,${CADDomainRootDn}"
        }
        ServiceAccounts = @{
            Description = "Data Safe Haven Service Accounts"
            Path        = "OU=Data Safe Haven Service Accounts,${CADDomainRootDn}"
        }
    }
    $DataSafeHavenServiceAccounts = @{
        AzureADSynchroniser = @{
            Description = "Azure Active Directory synchronisation manager"
            Password    = $CADAzureADConnectPassword
            Username    = $CADAzureADConnectUsername
        }
        ComputerManager     = @{
            Description = "DSH domain computers manager"
            Password    = $CADDomainComputerManagerPassword
            Username    = $CADDomainComputerManagerUsername
        }
    }
    $DataSafeHavenGroups = @{
        DataAdministrators   = @{
            Description = "Data Safe Haven Data Administrators"
            Members     = @()
        }
        ServerAdministrators = @{
            Description = "Data Safe Haven Server Administrators"
            Members     = @($CADDomainAdministratorUsername)
        }
    }
    $ADGuid = @{
        "lockoutTime"            = "28630ebf-41d5-11d1-a9c1-0000f80367c1";
        "mS-DS-ConsistencyGuid"  = "23773dc2-b63a-11d2-90e1-00c04fd91ab1";
        "msDS-KeyCredentialLink" = "5b47d60f-6090-40b2-9f37-2a4de88f3063";
        "pwdLastSet"             = "bf967a0a-0de6-11d0-a285-00aa003049e2";
        "user"                   = "bf967aba-0de6-11d0-a285-00aa003049e2";
    }
    $ADExtendedRights = @{
        "Change Password" = "ab721a53-1e2f-11d0-9819-00aa0040529b";
        "Reset Password"  = "00299570-246d-11d0-a768-00aa006e0529";
    }

    Node localhost {
        # Enable the AD recycle bin
        ADOptionalFeature RecycleBin { # from ActiveDirectoryDsc
            EnterpriseAdministratorCredential = $DomainAdministratorCredentials
            FeatureName = "Recycle Bin Feature"
            ForestFQDN = $CADDomainName
        }

        # Set domain admin password to never expire
        ADUser SetAdminPasswordExpiry { # from ActiveDirectoryDsc
            UserName = $CADDomainAdministratorUsername
            DomainName = $CADDomainName
            PasswordNeverExpires = $true
        }

        # Disable domain admin minimum password age
        ADDomainDefaultPasswordPolicy SetAdminPasswordMinimumAge { # from ActiveDirectoryDsc
            Credential = $DomainAdministratorCredentials
            DomainName = $CADDomainName
            MinPasswordAge = 0
        }

        # Create organisational units
        foreach ($Unit in $DataSafeHavenUnits.Keys) {
            ADOrganizationalUnit "$Unit" { # from ActiveDirectoryDsc
                Credential = $DomainAdministratorCredentials
                Description = "$($DataSafeHavenUnits[$Unit].Description)"
                Ensure = "Present"
                Name = "$($DataSafeHavenUnits[$Unit].Description)"
                Path = $CADDomainRootDn
                ProtectedFromAccidentalDeletion = $true
            }
        }

        # Create service users
        foreach ($User in $DataSafeHavenServiceAccounts.Keys) {
            $UserCredentials = (New-Object System.Management.Automation.PSCredential ($DataSafeHavenServiceAccounts[$User].Username, (ConvertTo-SecureString -String $DataSafeHavenServiceAccounts[$User].Password -AsPlainText -Force)))
            ADUser "$User" {
                Description = "$($DataSafeHavenServiceAccounts[$User].Description)"
                DisplayName = "$($DataSafeHavenServiceAccounts[$User].Description)"
                DomainName = "$CADDomainName"
                Ensure = "Present"
                Password = $UserCredentials
                PasswordNeverExpires = $true
                Path = "$($DataSafeHavenUnits.ServiceAccounts.Path)"
                UserName = "$($UserCredentials.UserName)"
            }
        }

        # Create security groups
        foreach ($Group in $DataSafeHavenGroups.Keys) {
            ADGroup $Group { # from ActiveDirectoryDsc
                Category = "Security"
                Description = "$($DataSafeHavenGroups[$Group].Description)"
                Ensure = "Present"
                GroupName = "$($DataSafeHavenGroups[$Group].Description)"
                GroupScope = "Global"
                Members = $DataSafeHavenGroups[$Group].Members
                Path = $DataSafeHavenUnits.SecurityGroups.Path
            }
        }

        # Give write permissions to the local AD sync account
        foreach ($Property in @("lockoutTime", "pwdLastSet", "mS-DS-ConsistencyGuid", "msDS-KeyCredentialLink")) {
            ADObjectPermissionEntry "$Property" {
                AccessControlType = "Allow"
                ActiveDirectoryRights = "WriteProperty"
                ActiveDirectorySecurityInheritance = "Descendents"
                Ensure = "Present"
                IdentityReference = $DataSafeHavenServiceAccounts.AzureADSynchroniser.UserName
                InheritedObjectType = $ADGuid["user"]
                ObjectType = $ADGuid[$Property]
                Path = $CADDomainRootDn
                DependsOn = "[ADUser]AzureADSynchroniser"
            }
        }

        # Give extended rights to the local AD sync account
        foreach ($ExtendedRight in @("Change Password", "Reset Password")) {
            ADObjectPermissionEntry "$ExtendedRight" {
                AccessControlType = "Allow"
                ActiveDirectoryRights = "ExtendedRight"
                ActiveDirectorySecurityInheritance = "Descendents"
                Ensure = "Present"
                IdentityReference = $DataSafeHavenServiceAccounts.AzureADSynchroniser.UserName
                InheritedObjectType = $ADGuid["user"]
                ObjectType = $ADExtendedRights[$ExtendedRight]
                Path = $CADDomainRootDn
                DependsOn = "[ADUser]AzureADSynchroniser"
            }
        }

        # Allow the AzureAD synchroniser account to replicate directory changes
        Script SetAzureADSynchroniserPermissions {
            SetScript = {
                try {
                    $success = $true
                    $AzureADSyncUsername = $using:DataSafeHavenServiceAccounts.AzureADSynchroniser.Username
                    $AzureADSyncSID = (Get-ADUser -Identity $AzureADSyncUsername).SID
                    $DefaultNamingContext = $(Get-ADRootDSE).DefaultNamingContext
                    $ConfigurationNamingContext = $(Get-ADRootDSE).ConfigurationNamingContext
                    $null = dsacls "$($DefaultNamingContext)" /G "${AzureADSyncSID}:CA;Replicating Directory Changes"
                    $success = $success -and $?
                    $null = dsacls "$($ConfigurationNamingContext)" /G "${AzureADSyncSID}:CA;Replicating Directory Changes"
                    $success = $success -and $?
                    $null = dsacls "$($DefaultNamingContext)" /G "${AzureADSyncSID}:CA;Replicating Directory Changes All"
                    $success = $success -and $?
                    $null = dsacls "$($ConfigurationNamingContext)" /G "${AzureADSyncSID}:CA;Replicating Directory Changes All"
                    $success = $success -and $?
                    if ($success) {
                        Write-Verbose -Message "Successfully updated ACL permissions for AD Sync Service account '$AzureADSyncUsername'"
                    } else {
                        throw "Failed to update ACL permissions for AD Sync Service account '$AzureADSyncUsername'!"
                    }
                } catch {
                    Write-Error "SetAzureADSynchroniserPermissions: $($_.Exception)"
                }
            }
            GetScript = { @{} }
            TestScript = { $false }
            DependsOn = "[ADUser]AzureADSynchroniser"
        }

        # Allow the computer manager to register computers in the domain
        Script SetComputerManagerPermissions {
            SetScript = {
                try {
                    $success = $true
                    $DomainComputerManagerUsername = $using:DataSafeHavenServiceAccounts.ComputerManager.Username
                    # $OuDescription = $using:DataSafeHavenUnits.DomainComputers.Description
                    # $OrganisationalUnit = Get-ADObject -Filter "Name -eq '$OuDescription'"
                    $OrganisationalUnit = Get-ADObject -Filter "Name -eq '$($using:DataSafeHavenUnits.DomainComputers.Description)'"
                    $DomainComputerManagerSID = (Get-ADUser -Identity $DomainComputerManagerUsername).SID
                    # Add permission to create child computer objects
                    $null = dsacls $OrganisationalUnit /I:T /G "${userPrincipalName}:CC;computer"
                    $success = $success -and $?
                    # Give 'write property' permissions over several attributes of child computer objects
                    $null = dsacls $OrganisationalUnit /I:S /G "${DomainComputerManagerSID}:WP;DNS Host Name Attributes;computer"
                    $success = $success -and $?
                    $null = dsacls $OrganisationalUnit /I:S /G "${DomainComputerManagerSID}:WP;msDS-SupportedEncryptionTypes;computer"
                    $success = $success -and $?
                    $null = dsacls $OrganisationalUnit /I:S /G "${DomainComputerManagerSID}:WP;operatingSystem;computer"
                    $success = $success -and $?
                    $null = dsacls $OrganisationalUnit /I:S /G "${DomainComputerManagerSID}:WP;operatingSystemVersion;computer"
                    $success = $success -and $?
                    $null = dsacls $OrganisationalUnit /I:S /G "${DomainComputerManagerSID}:WP;operatingSystemServicePack;computer"
                    $success = $success -and $?
                    $null = dsacls $OrganisationalUnit /I:S /G "${DomainComputerManagerSID}:WP;sAMAccountName;computer"
                    $success = $success -and $?
                    $null = dsacls $OrganisationalUnit /I:S /G "${DomainComputerManagerSID}:WP;servicePrincipalName;computer"
                    $success = $success -and $?
                    $null = dsacls $OrganisationalUnit /I:S /G "${DomainComputerManagerSID}:WP;userPrincipalName;computer"
                    $success = $success -and $?
                    if ($success) {
                        Write-Verbose -Message "Successfully delegated Active Directory permissions on '$OrganisationalUnit' to '$DomainComputerManagerUsername'"
                    } else {
                        throw "Failed to delegate Active Directory permissions on '$OrganisationalUnit' to '$DomainComputerManagerUsername'!"
                    }
                } catch {
                    Write-Error "SetComputerManagerPermissions: $($_.Exception)"
                }
            }
            GetScript = { @{} }
            TestScript = { $false }
            DependsOn = "[ADUser]ComputerManager"
        }
    }
}

Configuration DownloadInstallers {
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Installer base path")]
        [ValidateNotNullOrEmpty()]
        [String]$DIInstallerBasePath
    )

    Import-DscResource -ModuleName xPSDesiredStateConfiguration -ModuleVersion 9.1.0

    Node localhost {
        Script AzureADConnect {
            SetScript = {
                try {
                    Invoke-RestMethod -Uri "https://download.microsoft.com/download/B/0/0/B00291D0-5A83-4DE7-86F5-980BC00DE05A/AzureADConnect.msi" -OutFile (Join-Path $using:DIInstallerBasePath "AzureADConnect.msi") -ErrorAction Stop
                    Write-Verbose -Message "Successfully downloaded AzureADConnect installer to '$using:DIInstallerBasePath'."
                } catch {
                    Write-Error "AzureADConnect: $($_.Exception)"
                }
            }
            GetScript = { @{} }
            TestScript = { (Test-Path -Path (Join-Path $using:DIInstallerBasePath "AzureADConnect.msi")) }
        }

        xRemoteFile DisconnectAD { # from xPSDesiredStateConfiguration
            Uri = "https://raw.githubusercontent.com/alan-turing-institute/data-safe-haven/develop/deployment/safe_haven_management_environment/desired_state_configuration/dc1Artifacts/Disconnect_AD.mustache.ps1"
            DestinationPath = Join-Path $DIInstallerBasePath "DisconnectAD.ps1"
        }
    }
}

Configuration PrimaryDomainController {
    param (
        [Parameter(Mandatory = $true, HelpMessage = "AzureAD connect password")]
        [ValidateNotNullOrEmpty()]
        [String]$AzureADConnectPassword,

        [Parameter(Mandatory = $true, HelpMessage = "AzureAD connect username")]
        [ValidateNotNullOrEmpty()]
        [String]$AzureADConnectUsername,

        [Parameter(Mandatory = $true, HelpMessage = "Domain administrator password")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainAdministratorPassword,

        [Parameter(Mandatory = $true, HelpMessage = "Domain administrator username")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainAdministratorUsername,

        [Parameter(Mandatory = $true, HelpMessage = "Domain computer manager password")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainComputerManagerPassword,

        [Parameter(Mandatory = $true, HelpMessage = "Domain computer manager username")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainComputerManagerUsername,

        [Parameter(Mandatory = $true, HelpMessage = "FQDN for the SHM domain")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainName,

        [Parameter(Mandatory = $true, HelpMessage = "Root DN for the SHM domain")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainRootDn,

        [Parameter(Mandatory = $true, HelpMessage = "NetBIOS name for the domain")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainNetBios
    )

    # Common parameters
    $DataSafeHavenBasePath = "C:\DataSafeHaven"
    $ActiveDirectoryBasePath = Join-Path $DataSafeHavenBasePath "ActiveDirectory"
    $InstallersBasePath = Join-Path $DataSafeHavenBasePath "Installers"

    Node localhost {
        InstallPowershellModules InstallPowershellModules {}

        Script CreateBaseDirectories {
            SetScript = {
                New-Item -ItemType Directory -Force -Path $using:DataSafeHavenBasePath
                Write-Verbose -Message "Ensured that $($using:DataSafeHavenBasePath) exists"
                New-Item -ItemType Directory -Force -Path $using:ActiveDirectoryBasePath
                Write-Verbose -Message "Ensured that $($using:ActiveDirectoryBasePath) exists"
                New-Item -ItemType Directory -Force -Path $using:InstallersBasePath
                Write-Verbose -Message "Ensured that $($using:InstallersBasePath) exists"
            }
            GetScript = { @{} }
            TestScript = { ((Test-Path -Path $using:ActiveDirectoryBasePath) -and (Test-Path -Path $using:InstallersBasePath)) }
        }

        InstallActiveDirectory InstallActiveDirectory {
            IADActiveDirectoryLogPath = Join-Path $ActiveDirectoryBasePath "Logs"
            IADActiveDirectoryNtdsPath = Join-Path $ActiveDirectoryBasePath "NTDS"
            IADActiveDirectorySysvolPath = Join-Path $ActiveDirectoryBasePath "SYSVOL"
            IADDomainAdministratorPassword = $DomainAdministratorPassword
            IADDomainAdministratorUsername = $DomainAdministratorUsername
            IADDomainName = $DomainName
            IADDomainNetBiosName = $DomainNetBios
            DependsOn = "[Script]CreateBaseDirectories"
        }

        ConfigureActiveDirectory ConfigureActiveDirectory {
            CADAzureADConnectPassword = $AzureADConnectPassword
            CADAzureADConnectUsername = $AzureADConnectUsername
            CADDomainAdministratorPassword = $DomainAdministratorPassword
            CADDomainAdministratorUsername = $DomainAdministratorUsername
            CADDomainComputerManagerPassword = $DomainComputerManagerPassword
            CADDomainComputerManagerUsername = $DomainComputerManagerUsername
            CADDomainName = $DomainName
            CADDomainRootDn = $DomainRootDn
            DependsOn = "[InstallActiveDirectory]InstallActiveDirectory"
        }

        DownloadInstallers DownloadInstallers {
            DIInstallerBasePath = $InstallersBasePath
            DependsOn = @("[Script]CreateBaseDirectories")
        }
    }
}
