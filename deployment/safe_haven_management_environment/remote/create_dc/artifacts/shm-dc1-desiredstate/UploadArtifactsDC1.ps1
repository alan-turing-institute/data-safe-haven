configuration UploadArtifactsDC1 {
    param (
        [Parameter(HelpMessage = "Base-64 encoded array of blob names to download from storage blob container")]
        [ValidateNotNullOrEmpty()]
        [string]$BlobNamesB64,

        [Parameter(HelpMessage = "Base-64 encoded SAS token with read/list rights to the storage blob container")]
        [ValidateNotNullOrEmpty()]
        [string]$BlobSasTokenB64,

        [Parameter(HelpMessage = "Name of the storage account")]
        [ValidateNotNullOrEmpty()]
        [string]$StorageAccountName,

        [Parameter(HelpMessage = "Name of the storage container")]
        [ValidateNotNullOrEmpty()]
        [string]$StorageContainerName,

        [Parameter(HelpMessage = "Absolute path to directory which blobs should be downloaded to")]
        [ValidateNotNullOrEmpty()]
        [string]$TargetDirectory
    )

    Node localhost {
        LocalConfigurationManager {
            RebootNodeIfNeeded = $true
            ConfigurationMode  = "ApplyOnly"
        }

        Script EmptyDirectory {
            SetScript  = {
                Write-Output "Clearing all pre-existing files and folders from '$using:TargetDirectory'"
                if (Test-Path -Path $using:TargetDirectory) {
                    Get-ChildItem $using:TargetDirectory -Recurse | Remove-Item -Recurse -Force
                } else {
                    New-Item -ItemType directory -Path $using:TargetDirectory
                }
            }
            GetScript  = { @{} }
            TestScript = { (Test-Path -Path $using:TargetDirectory) -and -not (Test-Path -Path "$using:TargetDirectory/*") }
        }

        Script DownloadArtifacts {
            SetScript  = {
                $BlobNames = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($using:BlobNamesB64)) | ConvertFrom-Json
                $BlobSasToken = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($using:BlobSasTokenB64))

                Write-Verbose -Verbose "Downloading $($BlobNames.Length) files to '$using:TargetDirectory'..."
                foreach ($BlobName in $BlobNames) {
                    # Ensure that local directory exists
                    $LocalDir = Join-Path $using:TargetDirectory $(Split-Path -Parent $BlobName)
                    if (-not (Test-Path -Path $LocalDir)) {
                        $null = New-Item -ItemType Directory -Path $LocalDir
                    }
                    $LocalFilePath = Join-Path $LocalDir (Split-Path -Leaf $BlobName)

                    # Download file from blob storage
                    $BlobUrl = "https://$($using:StorageAccountName).blob.core.windows.net/$($using:StorageContainerName)/${BlobName}${BlobSasToken}"
                    Write-Verbose -Verbose " [ ] Fetching $BlobUrl..."
                    $null = Invoke-WebRequest -Uri $BlobUrl -OutFile $LocalFilePath
                    if ($?) {
                        Write-Verbose -Verbose " [o] Succeeded"
                    } else {
                        Write-Error " [x] Failed!"
                    }
                }
            }
            GetScript  = { @{} }
            TestScript = { $false }
            DependsOn  = "[Script]EmptyDirectory"
        }

        Script ExtractGPOs {
            SetScript  = {
                Write-Verbose -Verbose "Extracting zip files..."
                Expand-Archive "$($using:TargetDirectory)\GPOs.zip" -DestinationPath $using:TargetDirectory -Force
                if ($?) {
                    Write-Verbose -Verbose " [o] Completed"
                } else {
                    Write-Error " [x] Failed to extract GPO zip files"
                }
            }
            GetScript  = { @{} }
            TestScript = { Test-Path -Path "$($using:TargetDirectory)/GPOs/*" }
            DependsOn  = "[Script]DownloadArtifacts"
        }

    }
}