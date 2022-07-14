configuration InstallPowershellModules {
    Import-DscResource -ModuleName PowerShellModule

    Node localhost {
        PSModuleResource MSOnline {
            Ensure      = "present"
            Module_Name = "MSOnline"
        }

        PSModuleResource PackageManagement {
            Ensure      = "present"
            Module_Name = "PackageManagement"
        }

        PSModuleResource PowerShellGet {
            Ensure      = "present"
            Module_Name = "PowerShellGet"
        }

        PSModuleResource PSWindowsUpdate {
            Ensure      = "present"
            Module_Name = "PSWindowsUpdate"
        }
    }
}


configuration CreatePrimaryDomainController {
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

        [Parameter(Mandatory=$true, HelpMessage = "Domain administrator credentials")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$DomainAdministratorCredentials,

        [Parameter(Mandatory=$true, HelpMessage = "FQDN for the SHM domain")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainFqdn,

        [Parameter(Mandatory=$true, HelpMessage = "NetBIOS name for the domain")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainNetBIOSName,

        [Parameter(Mandatory=$true, HelpMessage = "VM administrator safe mode credentials")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$SafeModeCredentials
    )

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryDsc
    Import-DscResource -ModuleName ComputerManagementDsc
    Import-DscResource -ModuleName NetworkingDsc

    # Construct variables for use in DSC modules
    $Interface = Get-NetAdapter | Where-Object Name -Like "Ethernet*" | Select-Object -First 1

    Node localhost {
        LocalConfigurationManager {
            ActionAfterReboot  = "ContinueConfiguration"
            ConfigurationMode  = "ApplyOnly"
            RebootNodeIfNeeded = $true
        }

        WindowsFeature DNS {
            Ensure = "Present"
            Name   = "DNS"
        }

        WindowsFeature DnsServer {
            Ensure    = "Present"
            Name      = "RSAT-DNS-Server"
            DependsOn  = "[WindowsFeature]DNS"
        }

        WindowsFeature ADDomainServices {
            Ensure     = "Present"
            Name       = "AD-Domain-Services"
        }

        WindowsFeature ADDSTools {
            Ensure     = "Present"
            Name       = "RSAT-ADDS-Tools"
        }

        WindowsFeature ADAdminCenter {
            Ensure    = "Present"
            Name      = "RSAT-AD-AdminCenter"
        }

        Script EnableDNSDiags {
            SetScript  = {
                Write-Verbose -Verbose "Enabling DNS client diagnostics"
                Set-DnsServerDiagnostics -All $true
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn  = "[WindowsFeature]DnsServer"
        }

        DnsServerAddress DnsServerAddress { # from NetworkingDsc
            Address        = "127.0.0.1"
            AddressFamily  = "IPv4"
            InterfaceAlias = $Interface.Name
            DependsOn      = "[WindowsFeature]DnsServer"
        }

        ADDomain PrimaryDomainController { # from ActiveDirectoryDsc
            Credential                    = $DomainAdministratorCredentials
            DatabasePath                  = $ActiveDirectoryNtdsPath
            DomainName                    = $DomainFqdn
            DomainNetBiosName             = $DomainNetBIOSName
            LogPath                       = $ActiveDirectoryLogPath
            SafeModeAdministratorPassword = $SafeModeCredentials
            SysvolPath                    = $ActiveDirectorySysvolPath
            DependsOn                     = @("[DnsServerAddress]DnsServerAddress", "[WindowsFeature]ADDomainServices", "[WindowsFeature]ADDSTools")
        }

        PendingReboot RebootAfterPromotion { # from ComputerManagementDsc
            Name      = "RebootAfterPromotion"
            DependsOn = "[ADDomain]PrimaryDomainController"
        }
    }
}


configuration UploadArtifacts {
    param (
        [Parameter(HelpMessage = "Absolute path to directory which blobs should be downloaded to")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsDirectory,

        [Parameter(HelpMessage = "Array of blob names to download from storage blob container")]
        [ValidateNotNullOrEmpty()]
        [PSCustomObject]$BlobNames,

        [Parameter(HelpMessage = "SAS token with read/list rights to the storage blob container")]
        [ValidateNotNullOrEmpty()]
        [string]$BlobSasToken,

        [Parameter(HelpMessage = "Name of the storage account")]
        [ValidateNotNullOrEmpty()]
        [string]$StorageAccountName,

        [Parameter(HelpMessage = "Name of the storage container")]
        [ValidateNotNullOrEmpty()]
        [string]$StorageContainerName
    )

    Node localhost {
        Script EmptyDirectory {
            SetScript  = {
                try {
                    Write-Verbose -Verbose "Clearing all pre-existing files and folders from '$using:ArtifactsDirectory'"
                    if (Test-Path -Path $using:ArtifactsDirectory) {
                        Get-ChildItem $using:ArtifactsDirectory -Recurse | Remove-Item -Recurse -Force
                    } else {
                        New-Item -ItemType directory -Path $using:ArtifactsDirectory
                    }
                } catch {
                    Write-Error "EmptyDirectory: $($_.Exception)"
                }
            }
            GetScript  = { @{} }
            TestScript = { (Test-Path -Path $using:ArtifactsDirectory) -and -not (Test-Path -Path "$using:ArtifactsDirectory/*") }
        }

        Script DownloadArtifacts {
            SetScript  = {
                try {
                    Write-Verbose -Verbose "Downloading $($using:BlobNames.Length) files to '$using:ArtifactsDirectory'..."
                    foreach ($BlobName in $using:BlobNames) {
                        # Ensure that local directory exists
                        $LocalDir = Join-Path $using:ArtifactsDirectory $(Split-Path -Parent $BlobName)
                        if (-not (Test-Path -Path $LocalDir)) {
                            $null = New-Item -ItemType Directory -Path $LocalDir
                        }
                        $LocalFilePath = Join-Path $LocalDir (Split-Path -Leaf $BlobName)

                        # Download file from blob storage
                        $BlobUrl = "https://$($using:StorageAccountName).blob.core.windows.net/$($using:StorageContainerName)/${BlobName}$($using:BlobSasToken)"
                        Write-Verbose -Verbose " [ ] Fetching $BlobUrl..."
                        $null = Invoke-WebRequest -Uri $BlobUrl -OutFile $LocalFilePath
                        if ($?) {
                            Write-Verbose -Verbose "Downloading $BlobUrl succeeded"
                        } else {
                            throw "Downloading $BlobUrl failed!"
                        }
                    }
                } catch {
                    Write-Error "DownloadArtifacts: $($_.Exception)"
                }
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn  = "[Script]EmptyDirectory"
        }
    }
}


configuration ConfigureActiveDirectory {
    param (
        [Parameter(Mandatory=$true, HelpMessage = "Domain administrator credentials")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$DomainAdministratorCredentials,

        [Parameter(HelpMessage = "Username for a user with domain admin privileges")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainAdminUsername,

        [Parameter(HelpMessage = "Fully-qualified SHM domain name")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainFqdn,

        [Parameter(HelpMessage = "Domain OU (eg. DC=TURINGSAFEHAVEN,DC=AC,DC=UK)")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainDn,

        [Parameter(Mandatory=$true, HelpMessage = "NetBIOS name for the domain")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainNetBIOSName,

        [Parameter(HelpMessage = "Array of OU names to create")]
        [ValidateNotNullOrEmpty()]
        [string[]]$OuNames,

        [Parameter(HelpMessage = "Array of security group names to create")]
        [ValidateNotNullOrEmpty()]
        [hashtable[]]$SecurityGroups,

        [Parameter(HelpMessage = "DN for service accounts OU")]
        [ValidateNotNullOrEmpty()]
        [string]$ServiceAccountsOuDn,

        [Parameter(HelpMessage = "User accounts to create")]
        [ValidateNotNullOrEmpty()]
        [hashtable[]]$UserAccounts
    )

    Import-DscResource -Module ActiveDirectoryDsc

    $localAdSyncUser = $UserAccounts | Where-Object { $_.key -eq "aadLocalSync" }
    $computerManagersSG  = $SecurityGroups | Where-Object { $_.key -eq "computerManagers" }
    $serverAdminsSG  = $SecurityGroups | Where-Object { $_.key -eq "serverAdmins" }
    $guidMap = @{
        "lockoutTime" = "28630ebf-41d5-11d1-a9c1-0000f80367c1";
        "mS-DS-ConsistencyGuid" = "23773dc2-b63a-11d2-90e1-00c04fd91ab1";
        "msDS-KeyCredentialLink" = "5b47d60f-6090-40b2-9f37-2a4de88f3063";
        "pwdLastSet" = "bf967a0a-0de6-11d0-a285-00aa003049e2";
        "user" = "bf967aba-0de6-11d0-a285-00aa003049e2";
    }
    $extendedrightsmap = @{
        "Change Password" = "ab721a53-1e2f-11d0-9819-00aa0040529b";
        "Reset Password" = "00299570-246d-11d0-a768-00aa006e0529";
    }

    Node localhost {
        # Create organisational units
        foreach ($ouName in $OuNames) {
            ADOrganizationalUnit $ouName { # from ActiveDirectoryDsc
                Credential                      = $DomainAdministratorCredentials
                Description                     = $ouName
                Ensure                          = "Present"
                Name                            = $ouName
                Path                            = $DomainDn
                ProtectedFromAccidentalDeletion = $true
            }
        }

        # Create service users
        foreach ($userAccount in $UserAccounts) {
            ADUser "$($userAccount.name)" {
                Description          = $userAccount.name
                DisplayName          = $userAccount.name
                DomainName           = $DomainFqdn
                Ensure               = "Present"
                Password             = $userAccount.credentials
                PasswordNeverExpires = $true
                Path                 = $ServiceAccountsOuDn
                UserName             = $userAccount.credentials.UserName
            }
        }

        # Create security groups
        foreach ($securityGroup in $SecurityGroups) {
            $Members = @()
            # Add domain admin to server administrators group
            if ($securityGroup.name -eq $serverAdminsSG.name) {
                $Members = @($DomainAdminUsername)
            # Add service users to computer managers group (except the localAdSync user)
            } elseif ($computerManagersSG.name -eq $serverAdminsSG.name) {
                $Members = $UserAccounts | Where-Object { $_.key -ne $localAdSyncUser.key } | ForEach-Object { $_.credentials.UserName }
            }
            ADGroup "$($securityGroup.name)" { # from ActiveDirectoryDsc
                Category    = "Security"
                Description = $securityGroup.name
                Ensure      = "Present"
                GroupName   = $securityGroup.name
                GroupScope  = "Global"
                Members     = $Members
                Path        = $SecurityGroup.dn
            }
        }

        # Enable the AD recycle bin
        ADOptionalFeature RecycleBin { # from ActiveDirectoryDsc
            EnterpriseAdministratorCredential = $DomainAdministratorCredentials
            FeatureName                       = "Recycle Bin Feature"
            ForestFQDN                        = $DomainFqdn
        }

        # Set domain admin password to never expire
        ADUser SetAdminPasswordExpiry {
            UserName             = $DomainAdminUsername
            DomainName           = $DomainFqdn
            PasswordNeverExpires = $true
        }

        # Disable minimum password age
        ADDomainDefaultPasswordPolicy DisableMinimumPasswordAge {
            Credential        = $DomainAdministratorCredentials
            DomainName        = $DomainFqdn
            MinPasswordAge    = 0
        }

        # Give write permissions to the local AD sync account
        foreach ($property in @("lockoutTime", "pwdLastSet", "mS-DS-ConsistencyGuid", "msDS-KeyCredentialLink")) {
            ADObjectPermissionEntry "$property" {
                AccessControlType                  = "Allow"
                ActiveDirectoryRights              = "WriteProperty"
                ActiveDirectorySecurityInheritance = "Descendents"
                Ensure                             = "Present"
                IdentityReference                  = "${DomainNetBIOSName}\$($localAdSyncUser.credentials.UserName)"
                InheritedObjectType                = $guidMap["user"]
                ObjectType                         = $guidmap[$property]
                Path                               = $DomainDn
            }
        }

        # Give extended rights to the local AD sync account
        foreach ($extendedRight in @("Change Password", "Reset Password")) {
            ADObjectPermissionEntry "$extendedRight" {
                AccessControlType                  = "Allow"
                ActiveDirectoryRights              = "ExtendedRight"
                ActiveDirectorySecurityInheritance = "Descendents"
                Ensure                             = "Present"
                IdentityReference                  = "${DomainNetBIOSName}\$($localAdSyncUser.credentials.UserName)"
                InheritedObjectType                = $guidMap["user"]
                ObjectType                         = $extendedrightsmap[$extendedRight]
                Path                               = $DomainDn
            }
        }

        # Allow the local AD sync account to replicate directory changes
        Script SetLocalAdSyncPermissions {
            SetScript  = {
                try {
                    $success = $true
                    $rootDse = Get-ADRootDSE
                    $aadLocalSyncSID = (Get-ADUser $using:localAdSyncUser.credentials.UserName).SID
                    $null = dsacls "$($rootDse.DefaultNamingContext)" /G "${aadLocalSyncSID}:CA;Replicating Directory Changes"
                    $success = $success -and $?
                    $null = dsacls "$($rootDse.ConfigurationNamingContext)" /G "${aadLocalSyncSID}:CA;Replicating Directory Changes"
                    $success = $success -and $?
                    $null = dsacls "$($rootDse.DefaultNamingContext)" /G "${aadLocalSyncSID}:CA;Replicating Directory Changes All"
                    $success = $success -and $?
                    $null = dsacls "$($rootDse.ConfigurationNamingContext)" /G "${aadLocalSyncSID}:CA;Replicating Directory Changes All"
                    $success = $success -and $?
                    if ($success) {
                        Write-Verbose -Verbose "Successfully updated ACL permissions for AD Sync Service account '$($using:localAdSyncUsercredentials.UserName)'"
                    } else {
                        throw "Failed to update ACL permissions for AD Sync Service account '$($using:localAdSyncUsercredentials.UserName)'!"
                    }
                } catch {
                    Write-Error "SetLocalAdSyncPermissions: $($_.Exception)"
                }
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn = "[ADUser]$($localAdSyncUser.name)"
        }

        # Delegate Active Directory permissions to users/groups that allow them to register computers in the domain
        Script SetComputerRegistrationPermissions {
            SetScript  = {
                try {
                    foreach ($userAccount in $using:UserAccounts) {
                        $success = $true
                        if (-not $userAccount.groupOu) { continue }
                        $organisationalUnit = Get-ADObject -Filter "distinguishedName -eq '$($userAccount.groupOu)'"
                        $userPrincipalName = "$($using:DomainNetBiosName)\$($userAccount.credentials.UserName)"
                        # Add permission to create child computer objects
                        $null = dsacls $organisationalUnit /I:T /G "${userPrincipalName}:CC;computer"
                        $success = $success -and $?
                        # Give 'write property' permissions over several attributes of child computer objects
                        $null = dsacls $organisationalUnit /I:S /G "${userPrincipalName}:WP;DNS Host Name Attributes;computer"
                        $success = $success -and $?
                        $null = dsacls $organisationalUnit /I:S /G "${userPrincipalName}:WP;msDS-SupportedEncryptionTypes;computer"
                        $success = $success -and $?
                        $null = dsacls $organisationalUnit /I:S /G "${userPrincipalName}:WP;operatingSystem;computer"
                        $success = $success -and $?
                        $null = dsacls $organisationalUnit /I:S /G "${userPrincipalName}:WP;operatingSystemVersion;computer"
                        $success = $success -and $?
                        $null = dsacls $organisationalUnit /I:S /G "${userPrincipalName}:WP;operatingSystemServicePack;computer"
                        $success = $success -and $?
                        $null = dsacls $organisationalUnit /I:S /G "${userPrincipalName}:WP;sAMAccountName;computer"
                        $success = $success -and $?
                        $null = dsacls $organisationalUnit /I:S /G "${userPrincipalName}:WP;servicePrincipalName;computer"
                        $success = $success -and $?
                        $null = dsacls $organisationalUnit /I:S /G "${userPrincipalName}:WP;userPrincipalName;computer"
                        $success = $success -and $?
                    }
                    if ($success) {
                        Write-Verbose -Verbose "Successfully delegated Active Directory permissions on '$($userAccount.groupOu)' to '$userPrincipalName'"
                    } else {
                        throw "Failed to delegate Active Directory permissions on '$($userAccount.groupOu)' to '$userPrincipalName'!"
                    }
                } catch {
                    Write-Error "SetComputerRegistrationPermissions: $($_.Exception)"
                }
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn = "[Script]SetLocalAdSyncPermissions"
        }
    }
}


configuration ApplyGroupPolicies {
    param (
        [Parameter(HelpMessage = "Path to Active Directory system volume")]
        [ValidateNotNullOrEmpty()]
        [string]$ActiveDirectorySysvolPath,

        [Parameter(HelpMessage = "Absolute path to directory which blobs should be downloaded to")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsDirectory,

        [Parameter(HelpMessage = "Fully-qualified SHM domain name")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainFqdn,

        [Parameter(HelpMessage = "Domain OU (eg. DC=TURINGSAFEHAVEN,DC=AC,DC=UK)")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainDn,

        [Parameter(HelpMessage = "Database servers OU name (eg. 'Secure Research Environment Database Servers')")]
        [ValidateNotNullOrEmpty()]
        [string]$OuNameDatabaseServers,

        [Parameter(HelpMessage = "Identity servers OU name (eg. 'Safe Haven Identity Servers')")]
        [ValidateNotNullOrEmpty()]
        [string]$OuNameIdentityServers,

        [Parameter(HelpMessage = "Linux servers OU name (eg. 'Secure Research Environment Linux Servers')")]
        [ValidateNotNullOrEmpty()]
        [string]$OuNameLinuxServers,

        [Parameter(HelpMessage = "RDS gateway servers OU name (eg. 'Secure Research Environment RDS Gateway Servers')")]
        [ValidateNotNullOrEmpty()]
        [string]$OuNameRdsGatewayServers,

        [Parameter(HelpMessage = "RDS session servers OU name (eg. 'Secure Research Environment RDS Session Servers')")]
        [ValidateNotNullOrEmpty()]
        [string]$OuNameRdsSessionServers,

        [Parameter(HelpMessage = "Research users OU name (eg. 'Safe Haven Research Users')")]
        [ValidateNotNullOrEmpty()]
        [string]$OuNameResearchUsers,

        [Parameter(HelpMessage = "Security groups OU name (eg. 'Safe Haven Security Groups')")]
        [ValidateNotNullOrEmpty()]
        [string]$OuNameSecurityGroups,

        [Parameter(HelpMessage = "Service accounts OU name (eg. 'Safe Haven Service Accounts')")]
        [ValidateNotNullOrEmpty()]
        [string]$OuNameServiceAccounts,

        [Parameter(HelpMessage = "Name of the server administrator group")]
        [ValidateNotNullOrEmpty()]
        [string]$ServerAdminSgName
    )

    # Construct variables for use in DSC modules
    $GpoOutputPath = Join-Path $ArtifactsDirectory "GPOs"

    Node localhost {
        Script ExtractGroupPolicies {
            SetScript  = {
                try {
                    Write-Verbose -Verbose "Extracting GPO zip files..."
                    Expand-Archive "$($using:ArtifactsDirectory)\GPOs.zip" -DestinationPath $using:ArtifactsDirectory -Force
                    if ($?) {
                        Write-Verbose -Verbose "Successfully extracted GPO zip files"
                    } else {
                        throw "Failed to extract GPO zip files"
                    }
                } catch {
                    Write-Error "ExtractGroupPolicies: $($_.Exception)"
                }
            }
            GetScript  = { @{} }
            TestScript = { Test-Path -Path "$($using:GpoOutputPath)/*" }
        }

        Script ImportGroupPolicies {
            SetScript  = {
                try {
                    Write-Verbose -Verbose "Importing GPOs..."
                    foreach ($sourceTargetPair in (("0AF343A0-248D-4CA5-B19E-5FA46DAE9F9C", "All servers - Local Administrators"),
                                                   ("EE9EF278-1F3F-461C-9F7A-97F2B82C04B4", "All Servers - Windows Update"),
                                                   ("742211F9-1482-4D06-A8DE-BA66101933EB", "All Servers - Windows Services"),
                                                   ("B0A14FC3-292E-4A23-B280-9CC172D92FD5", "Session Servers - Remote Desktop Control"))) {
                        $source, $target = $sourceTargetPair
                        $null = Import-GPO -BackupId "$source" -TargetName "$target" -Path $using:GpoOutputPath -CreateIfNeeded
                        if ($?) {
                            Write-Verbose -Verbose "Importing '$source' to '$target' succeeded"
                        } else {
                            throw "Importing '$source' to '$target' failed!"
                        }
                    }
                } catch {
                    Write-Error "ImportGroupPolicies: $($_.Exception)"
                }
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn  = "[Script]ExtractGroupPolicies"
        }

        Script LinkGroupPoliciesToOus {
            SetScript  = {
                try {
                    Write-Verbose -Verbose "Linking GPOs to OUs..."
                    foreach ($gpoOuNamePair in (("All servers - Local Administrators", "$using:OuNameDatabaseServers"),
                                                ("All servers - Local Administrators", "$using:OuNameIdentityServers"),
                                                ("All servers - Local Administrators", "$using:OuNameRdsSessionServers"),
                                                ("All servers - Local Administrators", "$using:OuNameRdsGatewayServers"),
                                                ("All Servers - Windows Services", "Domain Controllers"),
                                                ("All Servers - Windows Services", "$using:OuNameDatabaseServers"),
                                                ("All Servers - Windows Services", "$using:OuNameIdentityServers"),
                                                ("All Servers - Windows Services", "$using:OuNameRdsSessionServers"),
                                                ("All Servers - Windows Services", "$using:OuNameRdsGatewayServers"),
                                                ("All Servers - Windows Update", "Domain Controllers"),
                                                ("All Servers - Windows Update", "$using:OuNameDatabaseServers"),
                                                ("All Servers - Windows Update", "$using:OuNameIdentityServers"),
                                                ("All Servers - Windows Update", "$using:OuNameRdsSessionServers"),
                                                ("All Servers - Windows Update", "$using:OuNameRdsGatewayServers"),
                                                ("Session Servers - Remote Desktop Control", "$using:OuNameRdsSessionServers"))) {
                        $gpoName, $ouName = $gpoOuNamePair
                        $gpo = Get-GPO -Name "$gpoName"
                        # Check for a match in existing GPOs
                        [xml]$gpoReportXML = Get-GPOReport -Guid $gpo.Id -ReportType xml
                        $hasGPLink = (@($gpoReportXML.GPO.LinksTo | Where-Object { ($_.SOMName -like "*${ouName}*") -and ($_.SOMPath -eq "$($using:DomainFqdn)/${ouName}") }).Count -gt 0)
                        # Create a GP link if it doesn't already exist
                        if ($hasGPLink) {
                            Write-Verbose -Verbose "GPO '$gpoName' already linked to '$ouName'"
                        } else {
                            $null = New-GPLink -Guid $gpo.Id -Target "OU=${ouName},$($using:DomainDn)" -LinkEnabled Yes
                            if ($?) {
                                Write-Verbose -Verbose "Linking GPO '$gpoName' to '$ouName' succeeded"
                            } else {
                                throw "Linking GPO '$gpoName' to '$ouName' failed!"
                            }
                        }
                    }
                } catch {
                    Write-Error "LinkGroupPoliciesToOus: $($_.Exception)"
                }
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn  = "[Script]ImportGroupPolicies"
        }

        Script GiveDomainAdminsLocalPrivileges {
            SetScript  = {
                try {
                    # Get SID for the Local Administrators group
                    $localAdminGroupName = "All servers - Local Administrators"
                    $localAdminGpo = Get-GPO -Name $localAdminGroupName
                    [xml]$gpoReportXML = Get-GPOReport -Guid $localAdminGpo.ID -ReportType xml
                    foreach ($group in $gpoReportXML.GPO.Computer.ExtensionData.Extension.RestrictedGroups) {
                        if ($group.GroupName.Name.'#text' -eq "BUILTIN\Administrators") {
                            $localAdminGroupSID = $group.GroupName.SID.'#text'
                        }
                    }
                    if ($localAdminGroupSID) {
                        Write-Verbose -Verbose "Local admin group '$localAdminGroupName' group has ID $localAdminGroupSID"
                    } else {
                        throw "ID for local admin group '$localAdminGroupName' could not be found!"
                    }

                    # Edit GptTmpl file controlling which domain users should be considered local administrators
                    Write-Verbose -Verbose "Ensuring that members of '$using:serverAdminSgName' are local administrators"
                    $GptTmplString = @(
                        '[Unicode]',
                        'Unicode=yes',
                        '[Version]',
                        'signature="$CHICAGO$"',
                        'Revision=1',
                        '[Group Membership]',
                        "*${localAdminGroupSID}__Memberof =",
                        "*${localAdminGroupSID}__Members = $using:serverAdminSgName"
                    ) -join "`n"
                    Set-Content -Path "$($using:ActiveDirectorySysvolPath)\domain\Policies\{$($localAdminGpo.ID)}\Machine\Microsoft\Windows NT\SecEdit\GptTmpl.inf" -Value "$GptTmplString"
                    if ($?) {
                        Write-Verbose -Verbose "Successfully set group policies for 'Local Administrators'"
                    } else {
                        throw "Failed to set group policies for 'Local Administrators'"
                    }
                } catch {
                    Write-Error "GiveDomainAdminsLocalPrivileges: $($_.Exception)"
                }
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn  = "[Script]ImportGroupPolicies"
        }

        Script SetRemoteDesktopServerLayout {
            SetScript  = {
                try {
                    Write-Verbose -Verbose "Setting the layout file for the Remote Desktop servers..."
                    $null = Set-GPRegistryValue -Key "HKCU\Software\Policies\Microsoft\Windows\Explorer\" `
                                                -Name "Session Servers - Remote Desktop Control" `
                                                -Type "ExpandString" `
                                                -ValueName "StartLayoutFile" `
                                                -Value "\\$($using:DomainFqdn)\SYSVOL\$($using:DomainFqdn)\scripts\ServerStartMenu\LayoutModification.xml"
                    if ($?) {
                        Write-Verbose -Verbose "Setting the layout file for the Remote Desktop servers succeeded"
                    } else {
                        throw "Setting the layout file for the Remote Desktop servers failed!"
                    }
                } catch {
                    Write-Error "SetRemoteDesktopServerLayout: $($_.Exception)"
                }
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn  = "[Script]ImportGroupPolicies"
        }
    }
}


configuration ConfigurePrimaryDomainController {
    param (
        [Parameter(Mandatory=$true, HelpMessage = "Active Directory base path")]
        [ValidateNotNullOrEmpty()]
        [string]$ActiveDirectoryBasePath,

        [Parameter(Mandatory=$true, HelpMessage = "VM administrator credentials")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$AdministratorCredentials,

        [Parameter(Mandatory=$true, HelpMessage = "Base-64 encoded array of blob names to download from storage blob container")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsBlobNamesB64,

        [Parameter(Mandatory=$true, HelpMessage = "Base-64 encoded SAS token with read/list rights to the storage blob container")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsBlobSasTokenB64,

        [Parameter(Mandatory=$true, HelpMessage = "Name of the artifacts storage account")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsStorageAccountName,

        [Parameter(Mandatory=$true, HelpMessage = "Name of the artifacts storage container")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsStorageContainerName,

        [Parameter(Mandatory=$true, HelpMessage = "Absolute path to directory which blobs should be downloaded to")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsTargetDirectory,

        [Parameter(Mandatory=$true, HelpMessage = "Domain OU (eg. DC=TURINGSAFEHAVEN,DC=AC,DC=UK)")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainDn,

        [Parameter(Mandatory=$true, HelpMessage = "FQDN for the SHM domain")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainFqdn,

        [Parameter(Mandatory=$true, HelpMessage = "NetBIOS name for the domain")]
        [ValidateNotNullOrEmpty()]
        [String]$DomainNetBIOSName,

        [Parameter(Mandatory=$true, HelpMessage = "Base-64 encoded domain organisational units")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainOusB64,

        [Parameter(Mandatory=$true, HelpMessage = "Base64-encoded security groups")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainSecurityGroupsB64,

        [Parameter(Mandatory=$true, HelpMessage = "VM administrator safe mode credentials")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$SafeModeCredentials,

        [Parameter(Mandatory=$true, HelpMessage = "Base-64 encoded user accounts")]
        [ValidateNotNullOrEmpty()]
        [string]$UserAccountsB64
    )

    # Construct variables for passing to DSC configurations
    $activeDirectoryLogPath = Join-Path $ActiveDirectoryBasePath "Logs"
    $activeDirectoryNtdsPath = Join-Path $ActiveDirectoryBasePath "NTDS"
    $activeDirectorySysvolPath = Join-Path $ActiveDirectoryBasePath "SYSVOL"
    $artifactsBlobNames = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ArtifactsBlobNamesB64)) | ConvertFrom-Json
    $artifactsBlobSasToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ArtifactsBlobSasTokenB64))
    $domainAdministratorCredentials = New-Object System.Management.Automation.PSCredential ("${DomainFqdn}\$($AdministratorCredentials.UserName)", $AdministratorCredentials.Password)
    $domainOus = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($DomainOusB64)) | ConvertFrom-Json
    $ouNames = $domainOus.PSObject.Members | Where-Object { $_.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject" } | ForEach-Object { $_.Value.name }
    $securityGroups = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($DomainSecurityGroupsB64)) | ConvertFrom-Json
    $securityGroupsHashtable = $securityGroups | ForEach-Object { $_.PSObject.Members } | Where-Object { $_.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject" } | ForEach-Object { @{ "key" = $_.Name; "name" = $_.Value.name; "dn" = "OU=$($domainOus.securityGroups.name),${DomainDn}" } }
    $userAccountsHashtable = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($UserAccountsB64)) | ConvertFrom-Json | ForEach-Object { $_.PSObject.Members } | Where-Object { $_.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject" } | ForEach-Object { @{ "key" = $_.Name; "name" = $_.Value.name; "groupOu" = $domainOus."$($_.Name)".path; "credentials" = (New-Object System.Management.Automation.PSCredential ($_.Value.samAccountName, (ConvertTo-SecureString $_.Value.password -AsPlainText -Force))) } }

    Node localhost {
        InstallPowershellModules InstallPowershellModules {}

        CreatePrimaryDomainController CreatePrimaryDomainController {
            ActiveDirectoryLogPath         = $activeDirectoryLogPath
            ActiveDirectoryNtdsPath        = $activeDirectoryNtdsPath
            ActiveDirectorySysvolPath      = $activeDirectorySysvolPath
            DomainAdministratorCredentials = $domainAdministratorCredentials
            DomainFqdn                     = $DomainFqdn
            DomainNetBiosName              = $DomainNetBiosName
            SafeModeCredentials            = $SafeModeCredentials
        }

        UploadArtifacts UploadArtifacts {
            BlobNames            = $artifactsBlobNames
            BlobSasToken         = $artifactsBlobSasToken
            StorageAccountName   = $ArtifactsStorageAccountName
            StorageContainerName = $ArtifactsStorageContainerName
            ArtifactsDirectory   = $ArtifactsTargetDirectory
            DependsOn            = "[CreatePrimaryDomainController]CreatePrimaryDomainController"
        }

        ConfigureActiveDirectory ConfigureActiveDirectory {
            DomainAdministratorCredentials = $domainAdministratorCredentials
            DomainAdminUsername            = $AdministratorCredentials.UserName
            DomainFqdn                     = $DomainFqdn
            DomainDn                       = $DomainDn
            DomainNetBiosName              = $DomainNetBiosName
            OuNames                        = $ouNames
            SecurityGroups                 = $securityGroupsHashtable
            ServiceAccountsOuDn            = "OU=$($domainOus.serviceAccounts.name),${DomainDn}"
            UserAccounts                   = $userAccountsHashtable
            DependsOn                      = @("[CreatePrimaryDomainController]CreatePrimaryDomainController", "[UploadArtifacts]UploadArtifacts")
        }

        ApplyGroupPolicies ApplyGroupPolicies {
            ActiveDirectorySysvolPath = $activeDirectorySysvolPath
            ArtifactsDirectory        = $ArtifactsTargetDirectory
            DomainFqdn                = $DomainFqdn
            DomainDn                  = $DomainDn
            OuNameDatabaseServers     = $domainOus.databaseServers.name
            OuNameIdentityServers     = $domainOus.identityServers.name
            OuNameLinuxServers        = $domainOus.linuxServers.name
            OuNameRdsGatewayServers   = $domainOus.rdsGatewayServers.name
            OuNameRdsSessionServers   = $domainOus.rdsSessionServers.name
            OuNameResearchUsers       = $domainOus.researchUsers.name
            OuNameSecurityGroups      = $domainOus.securityGroups.name
            OuNameServiceAccounts     = $domainOus.serviceAccounts.name
            ServerAdminSgName         = $securityGroups.serverAdmins.name
            DependsOn                 = @("[UploadArtifacts]UploadArtifacts", "[ConfigureActiveDirectory]ConfigureActiveDirectory")
        }
    }
}
