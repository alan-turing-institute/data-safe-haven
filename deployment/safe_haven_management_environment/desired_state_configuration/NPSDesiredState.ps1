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
            SetScript = {
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
            GetScript = { @{} }
            TestScript = { (Test-Path -Path $using:ArtifactsDirectory) -and -not (Test-Path -Path "$using:ArtifactsDirectory/*") }
        }

        Script DownloadArtifacts {
            SetScript = {
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
            GetScript = { @{} }
            TestScript = { $false }
            DependsOn = "[Script]EmptyDirectory"
        }
    }
}


configuration CreateNetworkPolicyServer {
    param (
        [Parameter(HelpMessage = "Path to the NPS MFA plugin installer")]
        [ValidateNotNullOrEmpty()]
        [string]$AzureMfaInstallerPath,

        [Parameter(HelpMessage = "Path to the NPS policy XML file")]
        [ValidateNotNullOrEmpty()]
        [string]$NpsPolicyXmlPath
    )

    Node localhost {
        WindowsFeature NPAS {
            Ensure = "Present"
            Name = "NPAS"
        }

        WindowsFeature NPASTools {
            Ensure = "Present"
            Name = "RSAT-NPAS"
            DependsOn = "[WindowsFeature]NPAS"
        }

        Script InstallNpsExtension {
            SetScript = {
                try {
                    Write-Verbose -Verbose "Installing NPS extension..."
                    Start-Process -FilePath $using:AzureMfaInstallerPath -ArgumentList '/install', '/quiet'
                    if ($?) {
                        Write-Verbose -Verbose "Successfully installed NPS extension"
                    } else {
                        throw "Failed to install NPS extension!"
                    }
                } catch {
                    Write-Error "InstallNpsExtension: $($_.Exception)"
                }
            }
            GetScript = { @{} }
            TestScript = { $false }
            DependsOn = "[WindowsFeature]NPASTools"
        }

        Script ImportNpsConditionalAccessPolicy {
            SetScript = {
                try {
                    Write-Verbose -Verbose "Importing NPS configuration for RDG_CAP policy..."
                    Import-NpsConfiguration -Path $using:NpsPolicyXmlPath
                } catch {
                    Write-Error "ImportNpsConditionalAccessPolicy: $($_.Exception)"
                }
            }
            GetScript = { @{} }
            TestScript = { $false }
            DependsOn = "[Script]InstallNpsExtension"
        }
    }
}


configuration ConfigureNetworkPolicyServer {
    param (
        [Parameter(Mandatory = $true, HelpMessage = "Base-64 encoded array of blob names to download from storage blob container")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsBlobNamesB64,

        [Parameter(Mandatory = $true, HelpMessage = "Base-64 encoded SAS token with read/list rights to the storage blob container")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsBlobSasTokenB64,

        [Parameter(Mandatory = $true, HelpMessage = "Name of the artifacts storage account")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsStorageAccountName,

        [Parameter(Mandatory = $true, HelpMessage = "Name of the artifacts storage container")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsStorageContainerName,

        [Parameter(Mandatory = $true, HelpMessage = "Absolute path to directory which blobs should be downloaded to")]
        [ValidateNotNullOrEmpty()]
        [string]$ArtifactsTargetDirectory
    )

    # Construct variables for passing to DSC configurations
    $artifactsBlobNames = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ArtifactsBlobNamesB64)) | ConvertFrom-Json
    $artifactsBlobSasToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($ArtifactsBlobSasTokenB64))
    $azureMfaInstallerPath = (Join-Path $ArtifactsTargetDirectory "NpsExtnForAzureMfaInstaller.exe")
    $npsPolicyXmlPath = (Join-Path $ArtifactsTargetDirectory "nps_config.xml")

    Node localhost {
        InstallPowershellModules InstallPowershellModules {}

        UploadArtifacts UploadArtifacts {
            BlobNames = $artifactsBlobNames
            BlobSasToken = $artifactsBlobSasToken
            StorageAccountName = $ArtifactsStorageAccountName
            StorageContainerName = $ArtifactsStorageContainerName
            ArtifactsDirectory = $ArtifactsTargetDirectory
            DependsOn = "[InstallPowershellModules]InstallPowershellModules"
        }

        CreateNetworkPolicyServer CreateNetworkPolicyServer {
            AzureMfaInstallerPath = $azureMfaInstallerPath
            NpsPolicyXmlPath = $npsPolicyXmlPath
            DependsOn = "[UploadArtifacts]UploadArtifacts"
        }
    }
}
