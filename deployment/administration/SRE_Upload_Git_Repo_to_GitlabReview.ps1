param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
    [string]$sreId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter the git URL of the source repository")]
    [string]$sourceGitURL,
    [Parameter(Mandatory = $true, HelpMessage = "Enter the full commit hash of the commit in the source repository to snapshot")]
    [string]$sourceCommitHash,
    [Parameter(Mandatory = $true, HelpMessage = "Enter the desired branch name where the snapshot should be placed (in the repository inside SRE GITLAB)")]
    [string]$targetBranchName,
    [Parameter(Mandatory = $false, HelpMessage = "Enter the name of the repository as it should appear within SRE GITLAB (default is the basename of the final path segment of the git URL)")]
    [string]$targetRepoName
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Security.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../common/GenerateSasToken.psm1 -Force


# If no target repo name is provided then interpret the basename of the final path segment in a (possibly encoded) URI as the name of the repository
# --------------------------------------------------------------------------------------------------------------------------------------------------
if (-not $targetRepoName) {
    $targetRepoName = [uri]::UnescapeDataString((Split-Path -Path ([uri]$sourceGitURL).Segments[-1] -LeafBase))
}


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName
$workingDir = Get-Location


# Create local zip file
# ---------------------
# The zipfile is called 'repo.zip', with the following contents:
#
# repo/
#   sourceGitURL
#   targetRepoName
#   sourceCommitHash
#   targetBranchName
#   snapshot/
#     ... repository contents
$zipFileName = "repo.zip"
Add-LogMessage -Level Info "[ ] Creating local zip file '$zipFileName' using $sourceCommitHash from $sourceGitURL"

# Create temporary directory and switch to it
$basePath = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()))
$repoPath = Join-Path $basePath "repo"
New-Item -ItemType Directory -Path $repoPath

# Checkout the repository and strip out its git history
$snapshotPath = Join-Path $repoPath "snapshot"
git clone $sourceGitURL $snapshotPath
Set-Location $snapshotPath
git checkout $sourceCommitHash
Remove-Item -Path (Join-Path $snapshotPath ".git") -Recurse -Force

## Record some metadata about the repository
Set-Location $repoPath
$sourceGitURL > sourceGitURL
$targetRepoName > targetRepoName
$sourceCommitHash > sourceCommitHash
$targetBranchName > targetBranchName

# Zip contents and meta
Set-Location $basePath
$zipFilePath = Join-Path $basePath $zipFileName
Compress-Archive -CompressionLevel NoCompression -Path $repoPath -DestinationPath $zipFilePath
if ($?) {
    Add-LogMessage -Level Success "Successfully created zip file at $zipFilePath"
} else {
    Add-LogMessage -Level Fatal "Failed to create zip file at $zipFilePath!"
}
Set-Location $workingDir


# Upload the zipfile to blob storage
# ----------------------------------
$tmpContainerName = $config.sre.storage.artifacts.containers.gitlabAirlockName + "-" + [Guid]::NewGuid().ToString()
Add-LogMessage -Level Info "[ ] Uploading zipfile to container '$tmpContainerName'..."
$storageResourceGroupName = $config.sre.storage.artifacts.rg
$sreStorageAccount = Deploy-StorageAccount -Name $config.sre.storage.artifacts.accountName -ResourceGroupName $storageResourceGroupName -Location $config.sre.location
$null = Deploy-StorageContainer -Name $tmpContainerName -StorageAccount $sreStorageAccount
$null = Set-AzStorageBlobContent -Container $tmpContainerName -Context $sreStorageAccount.Context -File $zipFilePath -Blob $zipFileName -Force
if ($?) {
    Add-LogMessage -Level Success "Successfully uploaded zip file to '$tmpContainerName'"
} else {
    Add-LogMessage -Level Fatal "Failed to upload zip file to '$tmpContainerName'!"
}


# Generate a SAS token and construct URL
# --------------------------------------
Add-LogMessage -Level Info "[ ] Generating SAS token..."
$sasToken = New-ReadOnlyAccountSasToken -ResourceGroup $storageResourceGroupName -AccountName $sreStorageAccount.StorageAccountName -SubscriptionName $config.sre.subscriptionName
$remoteUrl = "https://$($sreStorageAccount.StorageAccountName).blob.core.windows.net/${tmpContainerName}/${zipFileName}${sasToken}"
Add-LogMessage -Level Success "Constructed upload URL $remoteUrl"


# Download the zipfile onto the remote machine
# --------------------------------------------
$sreAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
# Create remote script (make a subdirectory of /tmp/zipfiles and run CURL to download blob to there)
$script = @"
#!/bin/bash
mkdir -p /tmp/zipfiles/
tmpdir=`$(mktemp -d /tmp/zipfiles/XXXXXXXXXXXXXXXXXXXX)
curl -X GET -o `$tmpdir/${zipFileName} "${remoteUrl}"
chown -R ${sreAdminUsername}:${sreAdminUsername} /tmp/zipfiles/
"@
Add-LogMessage -Level Info "[ ] Running remote script to download zipfile onto $($config.sre.webapps.gitlabreview.vmName)"
$result = Invoke-RemoteScript -Shell "UnixShell" -Script $script -VMName $config.sre.webapps.gitlabreview.vmName -ResourceGroupName $config.sre.webapps.rg
Write-Output $result.Value


# Clean up zipfile and blob storage container
# -------------------------------------------
Add-LogMessage -Level Info "[ ] Cleaning up zipfile and blob storage container..."
Remove-Item -Path $zipFilePath
$success = $?
Remove-AzStorageContainer -Name $tmpContainerName -Context $sreStorageAccount.Context -Confirm $false
$success = $success -and $?
if ($success) {
    Add-LogMessage -Level Success "Successfully cleaned up resources"
} else {
    Add-LogMessage -Level Fatal "Failed to clean up resources!"
}

# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext
