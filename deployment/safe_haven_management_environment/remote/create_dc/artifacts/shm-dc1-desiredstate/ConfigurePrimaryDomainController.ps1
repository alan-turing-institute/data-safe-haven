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

        [Parameter(HelpMessage = "Array of OU names to create")]
        [ValidateNotNullOrEmpty()]
        [string[]]$OuNames,

        [Parameter(HelpMessage = "Array of security group names to create")]
        [ValidateNotNullOrEmpty()]
        [string[]]$SecurityGroupNames,

        [Parameter(HelpMessage = "DN for security groups ou")]
        [ValidateNotNullOrEmpty()]
        [string]$SecurityGroupsOuDn
    )

    Import-DscResource -Module ActiveDirectoryDsc

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

        # Create security groups
        foreach ($securityGroupName in $SecurityGroupNames) {
            ADGroup $securityGroupName { # from ActiveDirectoryDsc
                Category    = "Security"
                Description = $securityGroupName
                Ensure      = "Present"
                GroupName   = $securityGroupName
                GroupScope  = "Global"
                Path        = $SecurityGroupsOuDn
            }
        }

        # Enable the AD recycle bin
        ADOptionalFeature RecycleBin { # from ActiveDirectoryDsc
            EnterpriseAdministratorCredential = $DomainAdministratorCredentials
            FeatureName                       = "Recycle Bin Feature"
            ForestFQDN                        = $DomainFqdn
        }

        # Set domain admin password to never expire
        Script SetAdminPasswordExpiry {
            SetScript  = {
                try {
                    Write-Verbose -Verbose "Setting domain admin password to never expire..."
                    Set-ADUser -Identity $using:DomainAdminUsername -PasswordNeverExpires $true
                    if ($?) {
                        Write-Verbose -Verbose "Successfully set domain admin password expiry"
                    } else {
                        throw "Failed to set domain admin password expiry!"
                    }
                } catch {
                    Write-Error "SetAdminPasswordExpiry: $($_.Exception)"
                }
            }
            GetScript  = { @{} }
            TestScript = { $false }
        }

        ADDomainDefaultPasswordPolicy SetMinimumPasswordAge {
            Credential        = $DomainAdministratorCredentials
            DomainName        = $DomainFqdn
            MinPasswordAge    = 0
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

        [Parameter(Mandatory=$true, HelpMessage = "Base-64 domain organisational units")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainOusB64,

        [Parameter(Mandatory=$true, HelpMessage = "Base64-encoded security groups")]
        [ValidateNotNullOrEmpty()]
        [string]$DomainSecurityGroupsB64,

        [Parameter(Mandatory=$true, HelpMessage = "VM administrator safe mode credentials")]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCredential]$SafeModeCredentials
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
    $securityGroupNames = $securityGroups.PSObject.Members | Where-Object { $_.TypeNameOfValue -eq "System.Management.Automation.PSCustomObject" } | ForEach-Object { $_.Value.name }

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
            OuNames                        = $ouNames
            SecurityGroupNames             = $securityGroupNames
            SecurityGroupsOuDn             = "OU=$($domainOus.securityGroups.name),${DomainDn}"
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
