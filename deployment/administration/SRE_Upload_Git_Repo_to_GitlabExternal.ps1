param(
  [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
    [string]$sreId,
    [Parameter( Mandatory = $true, HelpMessage = "Enter repo URL")]
    [string]$repoURL,
    [Parameter( Mandatory = $true, HelpMessage = "Enter repo name")]
    [string]$repoName,
    [Parameter( Mandatory = $true, HelpMessage = "Enter commit hash of the desired commit on external repository")]
    [string]$commitHash,
    [Parameter( Mandatory = $true, HelpMessage = "Enter desired branch name for the project inside Safe Haven")]
    [string]$branchName
)

Import-Module Az
Import-Module $PSScriptRoot/../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../common/GenerateSasToken.psm1 -Force

# Get config and original context before changing subscription
# ------------------------------------------------------------
#$config = Get-ShmFullConfig $shmId
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName

# Create local zip file
# ---------------------
Add-LogMessage -Level Info "Creating zipfilepath."
$zipFileName = "${repoName}_${commitHash}_${branchName}.zip"
$zipFilePath = Join-Path $PSScriptRoot $zipFileName
$tempDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()) "")

Add-LogMessage -Level Info "About to git clone "
$tempDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()) "$repoName")

Invoke-Expression -Command "git clone $repoURL $tempDir"
$workingDir = Get-Location
Set-Location $tempDir
Invoke-Expression -Command "git checkout $commitHash"
# Remove the .git directory
Remove-Item -Path ".git" -Recurse -Force
# Zip this directory
if (Test-Path $zipFilePath) { Remove-Item $zipFilePath }
Compress-Archive -CompressionLevel NoCompression -Path $tempDir -DestinationPath $zipFilePath
if ($?) {
    Add-LogMessage -Level Success "Zip file creation succeeded! $zipFilePath"
} else {
    Add-LogMessage -Level Fatal "Zip file creation failed!"
}
Set-Location $workingDir


# Upload the zip file to the VM, via blob storage
# -----------------------------------------------

$gitlabExternalVmName = $config.sre.webapps.gitlab.external.vmName
# Go via blob storage - first create storage account if not already there
$resourceGroupName = $config.sre.webapps.rg
$sreStorageAccountName = $config.sre.storage.artifacts.accountName
$sreStorageAccount = Deploy-StorageAccount -Name $sreStorageAccountName -ResourceGroupName $resourceGroupName -Location $config.sre.location

# Create container if not already there
$containerName = $config.sre.storage.artifacts.containers.gitlabAirlockName
Add-LogMessage -Level Info "Creating blob storage container $containerName in storage account $sreStorageAccountName ..."
$_ = Deploy-StorageContainer -Name $containerName -StorageAccount $sreStorageAccount
# delete existing blobs on the container
$blobs = @(Get-AzStorageBlob -Container $containerName -Context $sreStorageAccount.Context)
$numBlobs = $blobs.Length
if ($numBlobs -gt 0) {
    Add-LogMessage -Level Info "[ ] deleting $numBlobs blobs aready in container '$containerName'..."
    $blobs | ForEach-Object { Remove-AzStorageBlob -Blob $_.Name -Container $containerName -Context $sreStorageAccount.Context -Force }
    while ($numBlobs -gt 0) {
        Start-Sleep -Seconds 5
        $numBlobs = (Get-AzStorageBlob -Container $containerName -Context $sreStorageAccount.Context).Length
    }
    if ($?) {
        Add-LogMessage -Level Success "Blob deletion succeeded"
    } else {
        Add-LogMessage -Level Fatal "Blob deletion failed!"
    }
}

# copy zipfile to blob storage
# ----------------------------
Add-LogMessage -Level Info "Upload zipfile to storage..."
Set-AzStorageBlobContent -Container $containerName -Context $sreStorageAccount.Context -File $zipFilePath -Blob $zipFileName -Force

# Download zipfile onto the remote machine
# ----------------------------------------
# Get a SAS token and construct URL
$sasToken = New-ReadOnlyAccountSasToken -ResourceGroup $resourceGroupName -AccountName $sreStorageAccount.StorageAccountName -SubscriptionName $config.sre.subscriptionName
$remoteUrl = "https://$($sreStorageAccount.StorageAccountName).blob.core.windows.net/${containerName}/${zipFileName}${sasToken}"
Add-LogMessage -Level Info "Got SAS token and URL $remoteUrl"

# Create remote script (make a directory /zfiles/ and run CURL to download blob to there)
$script = @"
#!/bin/bash
mkdir -p /zfiles
curl -X GET -o /zfiles/${zipFileName} "${remoteUrl}"
"@

Add-LogMessage -Level Info "[ ] Running remote script to download zipfile onto $gitlabExternalVmName"
$result = Invoke-RemoteScript -Shell "UnixShell" -Script $script -VMName $gitlabExternalVmName -ResourceGroupName $resourceGroupName

# clean up - remove the zipfile from local machine.
Add-LogMessage -Level Info "[ ] Removing original zipfile $zipFilePath"
Remove-Item -Path $zipFilePath


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
