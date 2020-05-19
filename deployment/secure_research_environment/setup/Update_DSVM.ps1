param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId,
    [Parameter(Position = 1,Mandatory = $true,HelpMessage = "Last octet of IP address eg. '160'")]
    [string]$ipLastOctet = (Read-Host -Prompt "Last octet of IP address eg. '160'"),
    [Parameter(Position = 2,Mandatory = $false,HelpMessage = "Enter VM size to use (or leave empty to use default)")]
    [string]$vmSize = ""
)

Import-Module Az
Import-Module $PSScriptRoot/../../common/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../common/Mirrors.psm1 -Force
Import-Module $PSScriptRoot/../../common/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Set common variables
# --------------------
$vmIpAddress = $config.sre.network.subnets.data.prefix + "." + $ipLastOctet
if (!$vmSize) { $vmSize = $config.sre.dsvm.vmSizeDefault }


# Ensure this IP address is being used and identify the NIC
# ---------------------------------------------------------
$existingNic = Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PrivateIpAddress -eq $vmIpAddress }
if (-not $existingNic) {
    Add-LogMessage -Level Fatal "Failed to find an existing network card with IP address '$vmIpAddress', aborting upgrade"
}
$existingNicName = $existingNic.Name


# Find the virtual machine associated with the NIC
# ------------------------------------------------
# $existingVm = Get-AzVM | Where-Object { $_.NetworkProfile.NetworkInterfaces[0].Id -eq $existingNic.Id }
$existingVmId = $existingNic.VirtualMachine.Id
$existingVm = Get-AzVM | Where-Object { $_.Id -eq $existingVmId }
if (-not $existingVm) {
    Add-LogMessage -Level Fatal "No VM associated with the network card '$existingNicName', aborting upgrade"
}
$existingVmName = $existingVm.Name


# Stop existing VM
# ----------------
Add-LogMessage -Level Info "[ ] Stopping old virtual machine."
$existingVmName = $existingVm.Name
$_ = Stop-AzVM -ResourceGroupName $existingVm.ResourceGroupName -Name $existingVmName -Force
if ($?) {
    Add-LogMessage -Level Success "VM stopping succeeded"
} else {
    Add-LogMessage -Level Fatal "VM stopping failed!"
}


# Find and snapshot the existing data disks
# -----------------------------------------
$dataDiskSuffixes = @("-SCRATCH-DISK", "-HOME-DISK")
$dataDisks = @()
$dataDiskNames = @()
$snapshots = @()
$snapshotNames = @()
foreach ($suffix in $dataDiskSuffixes) {
    # Find disk
    $diskName = $existingVmName + "$suffix"
    Add-LogMessage -Level Info "[ ] Locating data disk '$diskName'"
    $disk = Get-AzDisk -DiskName $diskName
    if ($disk) {
        Add-LogMessage -Level Success "Data disk found"
    } else {
        Add-LogMessage -Level Fatal "Data disk '$diskName' not found, aborting upgrade."
    }
    $dataDisks += $disk
    $dataDiskNames += $diskName

    # Snapshot disk
    Add-LogMessage -Level Info "[ ] Snapshotting disk '$diskName'."
    $snapshotConfig = New-AzSnapShotConfig -SourceUri $disk.Id -Location $config.sre.location -CreateOption copy
    $snapshotName = $existingVmName + $suffix + "-SNAPSHOT"
    $snapshot = New-AzSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotName -ResourceGroupName $existingVm.ResourceGroupName
    if ($snapshot) {
        Add-LogMessage -Level Success "Snapshot succeeded"
    } else {
        Add-LogMessage -Level Fatal "Snapshot failed!"
    }
    $snapshots += $snapshot
    $snapshotNames += $snapshotName
}
$scratchDisk = $dataDisks[0]
$scratchDiskName = $dataDiskNames[0]
$scratchDiskSnapshot = $snapshots[0]
$scratchDiskSnapshotName = $snapshotNames[0]
$homeDisk = $dataDisks[1]
$homeDiskName = $dataDiskNames[1]
$homeDiskSnapshot = $snapshots[1]
$homeDiskSnapshotName = $snapshotNames[1]


# Remove the existing VM
# ----------------------
# Add-LogMessage -Level Info "Deleting existing VM."
# $_ = Remove-AzVM -Name $existingVmName -ResourceGroupName $existingVm.ResourceGroupName -Force
# if ($?) {
#     Add-LogMessage -Level Success "VM removal succeeded"
# } else {
#     Add-LogMessage -Level Fatal "VM removal failed!"
# }


# Remove the existing disks
# -------------------------
# Add-LogMessage -Level Info "Deleting existing OS disk."
# $_ = Remove-AzDisk -Name $OsDiskName -ResourceGroupName $existingVm.ResourceGroupName -Force
# if ($?) {
#     Add-LogMessage -Level Success "Disk deletion succeeded"
# } else {
#     Add-LogMessage -Level Fatal "Disk deletion failed!"
# }
# Add-LogMessage -Level Info "Deleting existing scratch disk."
# $_ = Remove-AzDisk -Name $scratchDiskName -ResourceGroupName $existingVm.ResourceGroupName -Force
# if ($?) {
#     Add-LogMessage -Level Success "Disk deletion succeeded"
# } else {
#     Add-LogMessage -Level Fatal "Disk deletion failed!"
# }
# Add-LogMessage -Level Info "Deleting existing home disk."
# $_ = Remove-AzDisk -Name $homeDiskName -ResourceGroupName $existingVm.ResourceGroupName -Force
# if ($?) {
#     Add-LogMessage -Level Success "Disk deletion succeeded"
# } else {
#     Add-LogMessage -Level Fatal "Disk deletion failed!"
# }


# Get list of image versions
# --------------------------
Add-LogMessage -Level Info "Getting image type from gallery..."
if ($config.sre.dsvm.vmImageType -eq "Ubuntu") {
    $imageDefinition = "ComputeVM-Ubuntu1804Base"
} elseif ($config.sre.dsvm.vmImageType -eq "UbuntuTorch") {
    $imageDefinition = "ComputeVM-UbuntuTorch1804Base"
} elseif ($config.sre.dsvm.vmImageType -eq "DataScience") {
    $imageDefinition = "ComputeVM-DataScienceBase"
} elseif ($config.sre.dsvm.vmImageType -eq "DSG") {
    $imageDefinition = "ComputeVM-DsgBase"
} else {
    Add-LogMessage -Level Fatal "Could not interpret $($config.sre.dsvm.vmImageType) as an image type!"
}
Add-LogMessage -Level Success "Using image type $imageDefinition"


# Check that this is a valid version and then get the image ID
# ------------------------------------------------------------
$_ = Set-AzContext -Subscription $config.sre.dsvm.vmImageSubscription
$imageVersion = $config.sre.dsvm.vmImageVersion
Add-LogMessage -Level Info "Looking for image $imageDefinition version $imageVersion..."
try {
    $image = Get-AzGalleryImageVersion -ResourceGroup $config.sre.dsvm.vmImageResourceGroup -GalleryName $config.sre.dsvm.vmImageGallery -GalleryImageDefinitionName $imageDefinition -GalleryImageVersionName $imageVersion -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException]{
    $versions = Get-AzGalleryImageVersion -ResourceGroup $config.sre.dsvm.vmImageResourceGroup -GalleryName $config.sre.dsvm.vmImageGallery -GalleryImageDefinitionName $imageDefinition | Sort-Object Name | ForEach-Object { $_.Name } #Select-Object -Last 1
    Add-LogMessage -Level Error "Image version '$imageVersion' is invalid. Available versions are: $versions"
    $imageVersion = $versions | Select-Object -Last 1
    $userVersion = Read-Host -Prompt "Enter the version you would like to use (or leave empty to accept the default: '$imageVersion')"
    if ($versions.Contains($userVersion)) {
        $imageVersion = $userVersion
    }
    $image = Get-AzGalleryImageVersion -ResourceGroup $config.sre.dsvm.vmImageResourceGroup -GalleryName $config.sre.dsvm.vmImageGallery -GalleryImageDefinitionName $imageDefinition -GalleryImageVersionName $imageVersion -ErrorAction Stop
}
$imageVersion = $image.Name
Add-LogMessage -Level Success "Found image $imageDefinition version $imageVersion in gallery"
$_ = Set-AzContext -Subscription $config.sre.subscriptionName


# Set VM name including the image version.
# As only the first 15 characters are used in LDAP we structure the name to ensure these will be unique
# -----------------------------------------------------------------------------------------------------
$vmNamePrefix = "SRE-$($config.sre.id)-${ipLastOctet}-DSVM".ToUpper()
$vmName = "$vmNamePrefix-${imageVersion}".Replace(".","-")
$vmName = $vmName + "-NEW"


# Check that VNET and subnet exist
# --------------------------------
Add-LogMessage -Level Info "Looking for virtual network '$($config.sre.network.vnet.name)'..."
# $vnet = $null
try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.Name -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException]{
    Add-LogMessage -Level Fatal "Virtual network '$($config.sre.network.vnet.name)' could not be found!"
}
Add-LogMessage -Level Success "Found virtual network '$($vnet.Name)' in $($vnet.ResourceGroupName)"

Add-LogMessage -Level Info "Looking for subnet '$($config.sre.network.subnets.data.Name)'..."
$subnet = $vnet.subnets | Where-Object { $_.Name -eq $config.sre.network.subnets.data.Name }
if ($null -eq $subnet) {
    Add-LogMessage -Level Fatal "Subnet '$($config.sre.network.subnets.data.Name)' could not be found in virtual network '$($vnet.Name)'!"
}
Add-LogMessage -Level Success "Found subnet '$($subnet.Name)' in $($vnet.Name)"


# Set mirror URLs
# ---------------
Add-LogMessage -Level Info "Determining correct URLs for package mirrors..."
$addresses = Get-MirrorAddresses -cranIp $config.sre.mirrors.cran.ip -pypiIp $config.sre.mirrors.pypi.ip
Add-LogMessage -Level Success "CRAN: '$($addresses.cran.url)'"
Add-LogMessage -Level Success "PyPI server: '$($addresses.pypi.url)'"
Add-LogMessage -Level Success "PyPI host: '$($addresses.pypi.host)'"


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dataMountPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dataMountPassword
$dsvmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmAdminPassword
$dsvmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$dsvmDbAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmDbAdminPassword
$dsvmDbReaderPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmDbReaderPassword
$dsvmDbWriterPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmDbWriterPassword
$dsvmLdapPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmLdapPassword


# Construct the cloud-init yaml file for the target subscription
# --------------------------------------------------------------
Add-LogMessage -Level Info "Constructing cloud-init from template..."
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
$cloudInitFilePath = Get-ChildItem -Path $cloudInitBasePath | Where-Object { $_.Name -eq "cloud-init-compute-vm-sre-${sreId}.template.yaml" } | ForEach-Object { $_.FullName }
if (-not $cloudInitFilePath) { $cloudInitFilePath = Join-Path $cloudInitBasePath "cloud-init-compute-vm.template.yaml" }
$cloudInitTemplate = $(Get-Content $cloudInitFilePath -Raw).Replace("<datamount-password>", $dataMountPassword).
                                                            Replace("<datamount-username>", $config.sre.users.datamount.samAccountName).
                                                            Replace("<dataserver-hostname>", $config.sre.dataserver.hostname).
                                                            Replace("<dsvm-hostname>", $vmName).
                                                            Replace("<dsvm-ldap-password>", $dsvmLdapPassword).
                                                            Replace("<dsvm-ldap-username>", $config.sre.users.ldap.dsvm.samAccountName).
                                                            Replace("<mirror-host-pypi>", $addresses.pypi.host).
                                                            Replace("<mirror-url-cran>", $addresses.cran.url).
                                                            Replace("<mirror-url-pypi>", $addresses.pypi.url).
                                                            Replace("<shm-dc-hostname-lower>", $($config.shm.dc.hostname).ToLower()).
                                                            Replace("<shm-dc-hostname-upper>", $($config.shm.dc.hostname).ToUpper()).
                                                            Replace("<shm-fqdn-lower>", $($config.shm.domain.fqdn).ToLower()).
                                                            Replace("<shm-fqdn-upper>", $($config.shm.domain.fqdn).ToUpper()).
                                                            Replace("<shm-ldap-base-dn>", $config.shm.domain.userOuPath).
                                                            Replace("<sre-ldap-bind-dn>", "CN=$($config.sre.users.ldap.dsvm.Name),$($config.shm.domain.serviceOuPath)").
                                                            Replace("<sre-ldap-user-filter>", "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.Name),$($config.shm.domain.securityOuPath)))")


# Insert xrdp logo into the cloud-init template
# Please note that the logo has to be an 8-bit RGB .bmp with no alpha.
# If you want to use a size other than the default (240x140) the xrdp.ini will need to be modified appropriately
# --------------------------------------------------------------------------------------------------------------
$xrdpCustomLogoPath = Join-Path $PSScriptRoot ".." "cloud_init" "resources" "xrdp_custom_logo.bmp"
$input = Get-Content $xrdpCustomLogoPath -Raw -AsByteStream
$outputStream = New-Object IO.MemoryStream
$gzipStream = New-Object System.IO.Compression.GZipStream($outputStream, [Io.Compression.CompressionMode]::Compress)
$gzipStream.Write($input, 0, $input.Length)
$gzipStream.Close()
$xrdpCustomLogoEncoded = [Convert]::ToBase64String($outputStream.ToArray())
$outputStream.Close()
$cloudInitTemplate = $cloudInitTemplate.Replace("<xrdpCustomLogoEncoded>", $xrdpCustomLogoEncoded)


# Insert PyCharm defaults into the cloud-init template
# ----------------------------------------------------
$indent = "      "
foreach ($scriptName in @("jdk.table.xml",
                          "project.default.xml")) {
    $raw_script = Get-Content (Join-Path $PSScriptRoot ".." "cloud_init" "scripts" $scriptName) -Raw
    $indented_script = $raw_script -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
    $cloudInitTemplate = $cloudInitTemplate.Replace("${indent}<$scriptName>", $indented_script)
}


# Find boot diagnostics storage account
# -------------------------------------
$bootDiagnosticsAccount = Get-AzStorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg
if (-not $bootDiagnosticsAccount) {
    Add-LogMessage -Level Fatal "Boot diagnostics storage account not found!"
}


# Deploy NIC and data disks
# -------------------------
# $vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $subnet -PrivateIpAddress $vmIpAddress -Location $config.sre.location
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $subnet -PrivateIpAddress 10.150.2.161 -Location $config.sre.location

# Create disks from snapshots and delete snapshots
# ------------------------------------------------
$dataDisks = @()
For ($i=0; $i -lt $snapshots.Length; $i++) {
    $diskConfig = New-AzDiskConfig -Location $config.sre.location -SourceResourceId $snapshots[$i].Id -CreateOption Copy
    $diskName = $vmName + $dataDiskSuffixes[$i]
    Add-LogMessage -Level Info "[ ] Creating new disk '$diskName'"
    $disk = New-AzDisk -Disk $diskConfig -ResourceGroupName $config.sre.dsvm.rg -DiskName $diskName
    if ($disk) {
        Add-LogMessage -Level Success "Disk creation succeeded"
    } else {
        Add-LogMessage -Level Fatal "Disk creation failed!"
    }
    $dataDisks += $disk

    $snapshotName = $snapshotNames[$i]
    Add-LogMessage -Level Info "[ ] Deleting snapshot '$snapshotName'"
    $_ = Remove-AzSnapshot -ResourceGroupName $config.sre.dsvm.rg -SnapshotName $snapshotName -Force
    if ($?) {
        Add-LogMessage -Level Success "Snapshot deletion succeeded"
    } else {
        Add-LogMessage -Level Failure "Snapshot deletion failed!"
    }
}
$scratchDisk = $dataDisks[0]
$homeDisk = $dataDisks[1]


# -------------
$params = @{
    Name = $vmName
    Size = $vmSize
    AdminPassword = $dsvmAdminPassword
    AdminUsername = $dsvmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml = $cloudInitTemplate
    location = $config.sre.location
    NicId = $vmNic.Id
    OsDiskType = $config.sre.dsvm.osdisk.type
    ResourceGroupName = $config.sre.dsvm.rg
    DataDiskIds = @($homeDisk.Id,$scratchDisk.Id)
    ImageId = $image.Id
}
$_ = Deploy-UbuntuVirtualMachine @params


# Add new virtual machine to NSG
# ------------------------------
$secureNsg = Get-AzNetworkSecurityGroup -Name $config.sre.dsvm.nsg -ResourceGroupName $config.sre.network.vnet.rg


# VM must be off for us to switch NSG
# -----------------------------------
Add-LogMessage -Level Info "Switching to secure NSG '$($secureNsg.Name)'..."
Add-VmToNSG -VMName $vmName -NSGName $secureNsg.Name


# Create Postgres roles
# ---------------------
Add-LogMessage -Level Info "[ ] Ensuring Postgres DB roles and initial shared users exist on VM $vmName"
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "compute_vm" "scripts" "create_postgres_roles.sh"
$params = @{
    DBADMINROLE = "admin"
    DBADMINUSER = "dbadmin"
    DBADMINPWD = $dsvmDbAdminPassword
    DBWRITERROLE = "writer"
    DBWRITERUSER = "dbwriter"
    DBWRITERPWD = $dsvmDbWriterPassword
    DBREADERROLE = "reader"
    DBREADERUSER = "dbreader"
    DBREADERPWD = $dsvmDbReaderPassword
}
$result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
Write-Output $result.Value


# Create local zip file
# ---------------------
Add-LogMessage -Level Info "Creating smoke test package for the DSVM..."
$zipFilePath = Join-Path $PSScriptRoot "smoke_tests.zip"
$tempDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()) "smoke_tests")
Copy-Item (Join-Path $PSScriptRoot ".." ".." "dsvm_images" "packages") -Filter *.* -Destination (Join-Path $tempDir package_lists) -Recurse
Copy-Item (Join-Path $PSScriptRoot ".." "remote" "compute_vm" "tests") -Filter *.* -Destination (Join-Path $tempDir tests) -Recurse
if (Test-Path $zipFilePath) { Remove-Item $zipFilePath }
Add-LogMessage -Level Info "[ ] Creating zip file at $zipFilePath..."
Compress-Archive -CompressionLevel NoCompression -Path $tempDir -DestinationPath $zipFilePath
if ($?) {
    Add-LogMessage -Level Success "Zip file creation succeeded"
} else {
    Add-LogMessage -Level Fatal "Zip file creation failed!"
}
Remove-Item -Path $tempDir -Recurse -Force


# Upload the zip file to the compute VM
# -------------------------------------
Add-LogMessage -Level Info "Uploading smoke tests to the DSVM..."
$zipFileEncoded = [Convert]::ToBase64String((Get-Content $zipFilePath -Raw -AsByteStream))
Remove-Item -Path $zipFilePath
# Run remote script
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "compute_vm" "scripts" "upload_smoke_tests.sh"
$params = @{
    PAYLOAD = $zipFileEncoded
    ADMIN_USERNAME = $dsvmAdminUsername
};
Add-LogMessage -Level Info "[ ] Uploading and extracting smoke tests on $vmName"
$result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
Write-Output $result.Value


# Run remote diagnostic scripts
# -----------------------------
Add-LogMessage -Level Info "Running diagnostic scripts on VM $vmName..."
$params = @{
    TEST_HOST = $config.shm.dc.fqdn
    LDAP_USER = $config.sre.users.ldap.dsvm.samAccountName
    DOMAIN_LOWER = $config.shm.domain.fqdn
    SERVICE_PATH = "'$($config.shm.domain.serviceOuPath)'"
}
foreach ($scriptNamePair in (("LDAP connection", "check_ldap_connection.sh"),
                             ("name resolution", "restart_name_resolution_service.sh"),
                             ("realm join", "rerun_realm_join.sh"),
                             ("SSSD service", "restart_sssd_service.sh"),
                             ("xrdp service", "restart_xrdp_service.sh"))) {
    $name, $diagnostic_script = $scriptNamePair
    $scriptPath = Join-Path $PSScriptRoot ".." "remote" "compute_vm" "scripts" $diagnostic_script
    Add-LogMessage -Level Info "[ ] Configuring $name ($diagnostic_script) on compute VM '$vmName'"
    $result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
    $success = $?
    Write-Output $result.Value
    if ($success) {
        Add-LogMessage -Level Success "Configuring $name on $vmName was successful"
    } else {
        Add-LogMessage -Level Failure "Configuring $name on $vmName failed!"
    }
}


# Get private IP address for this machine
# ---------------------------------------
$privateIpAddress = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg).Id } | ForEach-Object { $_.IpConfigurations.PrivateIpAddress }
Add-LogMessage -Level Info "Deployment complete. This new VM can be accessed from the RDS at $privateIpAddress"


# Switch back to original subscription
# ------------------------------------
$_ = Set-AzContext -Context $originalContext
