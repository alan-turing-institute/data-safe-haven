param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/GenerateSasToken.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -Subscription $config.sre.subscriptionName


# Set constants used in this script
# ---------------------------------
$artifactsFolderNameConfig = "sre-dc-configuration"
$artifactsFolderNameCreate = "sre-dc-ad-setup-scripts"
$dcCreationZipFileName = "dc-create.zip"
$remoteUploadDir = "C:\Installation"


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dcAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$dcAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dcAdminPassword


# Ensure that storage resource group and storage account exist
# ------------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.storage.artifacts.rg -Location $config.sre.location
$storageAccount = Deploy-StorageAccount -Name $config.sre.storage.artifacts.accountName -ResourceGroupName $config.sre.storage.artifacts.rg -Location $config.sre.location


# Create blob storage containers
# ------------------------------
Add-LogMessage -Level Info "Ensuring that blob storage containers exist..."
foreach ($containerName in ($artifactsFolderNameConfig, $artifactsFolderNameCreate)) {
    $_ = Deploy-StorageContainer -Name $containerName -StorageAccount $storageAccount
    $blobs = @(Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context)
    $numBlobs = $blobs.Length
    if($numBlobs -gt 0){
        Add-LogMessage -Level Info "Deleting $numBlobs blobs aready in container '$containerName'..."
        $blobs | ForEach-Object {Remove-AzStorageBlob -Blob $_.Name -Container $containerName -Context $storageAccount.Context -Force}
        while($numBlobs -gt 0){
            Add-LogMessage -Level Info "Waiting for deletion of $numBlobs remaining blobs..."
            Start-Sleep -Seconds 10
            $numBlobs = (Get-AzStorageBlob -Container $containerName -Context $storageAccount.Context).Length
        }
    }
}


# Upload artifacts for configuring the DC
# ---------------------------------------
Add-LogMessage -Level Info "Uploading DC configuration files to storage account '$($config.sre.storage.artifacts.accountName)'..."
ForEach ($folderFilePair in (($artifactsFolderNameCreate, $dcCreationZipFileName),
                             ($artifactsFolderNameConfig, "GPOs.zip"),
                             ($artifactsFolderNameConfig, "StartMenuLayoutModification.xml"))) {
    $artifactsFolderName, $artifactsFileName = $folderFilePair
    $_ = Set-AzStorageBlobContent -Container $artifactsFolderName -Context $storageAccount.Context -File "$PSScriptRoot/artifacts/$artifactsFolderName/$artifactsFileName" -Force
    if ($?) {
        Add-LogMessage -Level Success "Uploaded '$artifactsFileName' to '$artifactsFolderName'"
    } else {
        Add-LogMessage -Level Fatal "Failed to upload '$artifactsFileName'!"
    }
}


# Get SAS token and location of artifacts
# ---------------------------------------
Add-LogMessage -Level Info "[ ] Obtaining SAS token..."
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.sre.subscriptionName -resourceGroup $config.sre.storage.artifacts.rg -accountName $config.sre.storage.artifacts.accountName
if ($?) {
    Add-LogMessage -Level Success "Obtaining SAS token succeeded"
} else {
    Add-LogMessage -Level Fatal "Obtaining SAS token failed!"
}
$artifactLocation = "https://$($config.sre.storage.artifacts.accountName).blob.core.windows.net/${artifactsFolderNameCreate}/${dcCreationZipFileName}"


# Ensure that boot diagnostics resource group and storage account exist
# ---------------------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.bootdiagnostics.rg -Location $config.sre.location
$_ = Deploy-StorageAccount -Name $config.sre.bootdiagnostics.accountName -ResourceGroupName $config.sre.bootdiagnostics.rg -Location $config.sre.location


# Ensure that DC resource group exists
# ------------------------------------
$_ = Deploy-ResourceGroup -Name $config.sre.dc.rg -Location $config.sre.location


# Deploy DC from template
# -----------------------
Add-LogMessage -Level Info "Deploying domain controller (DC) from template..."
$netbiosNameMaxLength = 15
if($config.sre.domain.netbiosName.length -gt $netbiosNameMaxLength) {
    throw "NetBIOS name must be no more than 15 characters long. '$($config.sre.domain.netbiosName)' is $($config.sre.domain.netbiosName.length) characters long."
}
$params = @{
    Administrator_Password = (ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force)
    Administrator_User = $dcAdminUsername
    Artifacts_Location = $artifactLocation
    Artifacts_Location_SAS_Token = (ConvertTo-SecureString $artifactSasToken -AsPlainText -Force)
    BootDiagnostics_Account_Name = $config.sre.bootdiagnostics.accountName
    DC_IP_Address = $config.sre.dc.ip
    DC_VM_Name = $config.sre.dc.vmName
    DC_VM_Size = $config.sre.dc.vmSize
    Domain_Name = $config.sre.domain.fqdn
    Domain_NetBios_Name = $config.sre.domain.netbiosName
    SRE_ID = $config.sre.id
    Virtual_Network_Name = $config.sre.network.vnet.name
    Virtual_Network_Resource_Group = $config.sre.network.vnet.rg
    Virtual_Network_Subnet = $config.sre.network.subnets.identity.name
}
Deploy-ArmTemplate -TemplatePath "$PSScriptRoot/sre-dc-template.json" -Params $params -ResourceGroupName $config.sre.dc.rg


# Import artifacts from blob storage
# ----------------------------------
Add-LogMessage -Level Info "Importing configuration artifacts for: $($config.sre.dc.vmName)..."
# Get list of blobs in the storage account
$blobNames = Get-AzStorageBlob -Container $artifactsFolderNameConfig -Context $storageAccount.Context | ForEach-Object { $_.Name }
$artifactSasToken = New-ReadOnlyAccountSasToken -subscriptionName $config.sre.subscriptionName -resourceGroup $config.sre.storage.artifacts.rg -accountName $config.sre.storage.artifacts.accountName
# Run import script remotely
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Import_Artifacts.ps1"
$params = @{
    remoteDir = "`"$remoteUploadDir`""
    pipeSeparatedBlobNames = "`"$($blobNames -join "|")`""
    storageAccountName = "`"$($config.sre.storage.artifacts.accountName)`""
    storageContainerName = "`"$artifactsFolderNameConfig`""
    sasToken = "`"$artifactSasToken`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dc.vmName -ResourceGroupName $config.sre.dc.rg -Parameter $params
Write-Output $result.Value


# Remotely set the OS language for the DC
# ---------------------------------------
Add-LogMessage -Level Info "Setting OS language for: $($config.sre.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot ".." ".." ".." "common_powershell" "remote" "Set_Windows_Locale.ps1"
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dc.vmName -ResourceGroupName $config.sre.dc.rg
Write-Output $result.Value


# Create users, groups and OUs
# ----------------------------
Add-LogMessage -Level Info "Creating users, groups and OUs for: $($config.sre.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Create_Users_Groups_OUs.ps1"
$params = @{
    sreNetbiosName = "`"$($config.sre.domain.netbiosName)`""
    sreDn = "`"$($config.sre.domain.dn)`""
    sreServerAdminSgName = "`"$($config.sre.domain.securityGroups.serverAdmins.name)`""
    sreDcAdminUsername = "`"$($dcAdminUsername)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dc.vmName -ResourceGroupName $config.sre.dc.rg -Parameter $params
Write-Output $result.Value


# Configure DNS
# -------------
Add-LogMessage -Level Info "Configuring DNS for: $($config.sre.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_DNS.ps1"
$params = @{
    identitySubnetCidr = "`"$($config.sre.network.subnets.identity.cidr)`""
    rdsSubnetCidr = "`"$($config.sre.network.subnets.rds.cidr)`""
    dataSubnetCidr = "`"$($config.sre.network.subnets.data.cidr)`""
    shmFqdn = "`"$($config.shm.domain.fqdn)`""
    shmDcIp = "`"$($config.shm.dc.ip)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dc.vmName -ResourceGroupName $config.sre.dc.rg -Parameter $params
Write-Output $result.Value


# Configure GPOs
# --------------
Add-LogMessage -Level Info "Configuring GPOs for: $($config.sre.dc.vmName)..."
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_GPOs.ps1"
$params = @{
    oubackuppath = "`"$remoteUploadDir\GPOs`""
    sreNetbiosName = "`"$($config.sre.domain.netbiosName)`""
    sreFqdn = "`"$($config.sre.domain.fqdn)`""
    sreDomainOu = "`"$($config.sre.domain.dn)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.sre.dc.vmName -ResourceGroupName $config.sre.dc.rg -Parameter $params
Write-Output $result.Value


# Restart the DC
# --------------
Add-LogMessage -Level Info "Restarting $($config.sre.dc.vmName)..."
Restart-AzVM -Name $config.sre.dc.vmName -ResourceGroupName $config.sre.dc.rg
if ($?) {
    Add-LogMessage -Level Success "Restarting DC succeeded"
} else {
    Add-LogMessage -Level Fatal "Restarting DC failed!"
}


# Create domain trust from SHM DC to SRE DC
# -----------------------------------------
Add-LogMessage -Level Info "Creating domain trust between: $($config.sre.domain.fqdn) and $($config.shm.domain.fqdn)..."
$_ = Set-AzContext -Subscription $config.shm.subscriptionName

# Encrypt password
$dcAdminPasswordEncrypted = ConvertTo-SecureString $dcAdminPassword -AsPlainText -Force | ConvertFrom-SecureString -Key (1..16)

# Run domain configuration script remotely
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "Configure_Domain_Trust.ps1"
$params = @{
    sreDcAdminPasswordEncrypted = "`"$dcAdminPasswordEncrypted`""
    sreDcAdminUsername = "`"$dcAdminUsername`""
    sreFqdn = "`"$($config.sre.domain.fqdn)`""
}
$result = Invoke-RemoteScript -Shell "PowerShell" -ScriptPath $scriptPath -VMName $config.shm.dc.vmName -ResourceGroupName $config.shm.dc.rg -Parameter $params
Write-Output $result.Value


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext