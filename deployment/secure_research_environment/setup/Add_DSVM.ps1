param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Last octet of IP address eg. '160'")]
    [string]$ipLastOctet = (Read-Host -Prompt "Last octet of IP address eg. '160'"),
    [Parameter(Position = 2, Mandatory = $false, HelpMessage = "Enter VM size to use (or leave empty to use default)")]
    [string]$vmSize = "",
    [Parameter(Position = 3, Mandatory = $false, HelpMessage = "Perform an in-place upgrade.")]
    [switch]$upgrade,
    [Parameter(Position = 4, Mandatory = $false, HelpMessage = "Force an in-place upgrade.")]
    [switch]$forceUpgrade
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Deployments -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Mirrors -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Networking -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Security -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $configId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Set VM name and size
# We need to ensure that the start of the name is unique as LDAP will truncate after 15 characters
# ------------------------------------------------------------------------------------------------
if (!$vmSize) { $vmSize = $config.sre.dsvm.vmSizeDefault }
$vmNamePrefix = "SRE-$($config.sre.id)-${ipLastOctet}-DSVM".ToUpper()
$vmName = "$vmNamePrefix-$($config.sre.dsvm.vmImage.version)".Replace(".", "-")


# Check whether this IP address has been used.
# --------------------------------------------
$existingNic = Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PrivateIpAddress -eq $finalIpAddress }
if ($existingNic) {
    Add-LogMessage -Level Info "Found an existing network card with IP address '$finalIpAddress'"
    if ($upgrade) {
        Add-LogMessage -Level Info "This NIC will be removed in the upgrade process"
    } else {
        if ($existingNic.VirtualMachine.Id) {
            Add-LogMessage -Level InfoSuccess "A DSVM already exists with IP address '$finalIpAddress'. No further action will be taken"
            $null = Set-AzContext -Context $originalContext -ErrorAction Stop
            exit 0
        } else {
            Add-LogMessage -Level Info "No VM is attached to this network card, removing it"
            $null = $existingNic | Remove-AzNetworkInterface -Force
            if ($?) {
                Add-LogMessage -Level Success "Network card removal succeeded"
            } else {
                Add-LogMessage -Level Fatal "Network card removal failed!"
            }
        }

    }
}


if ($upgrade) {
    # Attempt to find an existing virtual machine
    # -------------------------------------------
    $existingVm = Get-AzVM | Where-Object { $_.Name -match "$vmNamePrefix-\d-\d-\d{10}" }
    if ($existingVm) {
        if ($existingVm.Length -ne 1) {
            foreach ($vm in $existingVm) {
                $vmName = $vm.Name
                Add-LogMessage -Level Info "Candidate VM: '$vmName'"
            }
            Add-LogMessage -Level Fatal "Multiple candidate VMs found, aborting upgrade"
        } else {
            $existingVmName = $existingVm.Name
            Add-LogMessage -Level Info "Found an existing VM '$existingVmName'"
        }
    } else {
        Add-LogMessage -Level Warning "No existing VM found to upgrade"
    }

    # Ensure that an upgrade will occur
    # ---------------------------------
    if ($existingVm) {
        if ($existingVm.Name -eq $vmName -and -not $forceUpgrade) {
            Add-LogMessage -Level Info "The existing VM appears to be using the same image version, no upgrade will occur. Use -forceUpgrade to ignore this"
            $null = Set-AzContext -Context $originalContext -ErrorAction Stop
            exit 0
        }
    }

    # Stop existing VM
    # ----------------
    if ($existingVm) {
        Add-LogMessage -Level Info "[ ] Stopping existing virtual machine."
        $null = Stop-AzVM -ResourceGroupName $existingVm.ResourceGroupName -Name $existingVm.Name -Force
        if ($?) {
            Add-LogMessage -Level Success "VM stopping succeeded"
        } else {
            Add-LogMessage -Level Fatal "VM stopping failed!"
        }
    }

    # Find and snapshot the existing data disks
    # -----------------------------------------
    $dataDiskNames = @("SCRATCH", "HOME")
    $snapshots = @()
    $snapshotNames = @()
    foreach ($name in $dataDiskNames) {
        # First attempt to find a disk
        Add-LogMessage -Level Info "[ ] Locating '$name' disk"
        $disk = Get-AzDisk | Where-Object { $_.Name -match "$vmNamePrefix-\d-\d-\d{10}-$name-DISK" }

        # If there is a disk, take a snapshot
        if ($disk) {
            if ($disk.Length -ne 1) {
                Add-LogMessage -Level Fatal "Multiple candidate '$name' disks found, aborting upgrade"
            }

            Add-LogMessage -Level Success "Data disk found"
            $diskName = $disk.Name

            # Snapshot disk
            Add-LogMessage -Level Info "[ ] Snapshotting disk '$diskName'."
            $snapshotConfig = New-AzSnapshotConfig -SourceUri $disk.Id -Location $config.sre.location -CreateOption copy
            $snapshotName = "${vmNamePrefix}-${name}-DISK-SNAPSHOT"
            $snapshot = New-AzSnapshot -Snapshot $snapshotConfig -SnapshotName $snapshotName -ResourceGroupName $config.sre.dsvm.rg
            if ($snapshot) {
                Add-LogMessage -Level Success "Snapshot succeeded"
            } else {
                Add-LogMessage -Level Fatal "Snapshot failed!"
            }
            $snapshots += $snapshot
            $snapshotNames += $snapshotName

        # If there is no disk, look for an existing snapshot
        } else {
            Add-LogMessage -Level Info "'$name' disk not found, attempting to find existing snapshot"
            $snapshot = Get-AzSnapshot | Where-Object { $_.Name -match "$vmNamePrefix-$name-DISK-SNAPSHOT" }
            if ($snapshot) {
                if ($snapshot.Length -ne 1) {
                    Add-LogMessage -Level Fatal "Multiple candidate '$name' snapshots found, aborting upgrade"
                }
                Add-LogMessage -Level Success "Snapshot found"
                $snapshots += $snapshot
                $snapshotNames += $snapshot.Name
            } else {
                Add-LogMessage -Level Fatal "No disk or snapshot for '$name' found, aborting upgrade"
            }
        }
    }

    # Remove the existing VM
    # ----------------------
    if ($existingVm) {
        Add-LogMessage -Level Info "[ ] Deleting existing VM"
        $null = Remove-AzVM -Name $existingVmName -ResourceGroupName $config.sre.dsvm.rg -Force
        if ($?) {
            Add-LogMessage -Level Success "VM removal succeeded"
        } else {
            Add-LogMessage -Level Fatal "VM removal failed!"
        }
    }

    # Remove the existing NIC
    # -----------------------
    if ($existingNic) {
        Add-LogMessage -Level Info "[ ] Deleting existing NIC"
        $null = Remove-AzNetworkInterface -Name $existingNic.Name -ResourceGroupName $config.sre.dsvm.rg -Force
        if ($?) {
            Add-LogMessage -Level Success "NIC removal succeeded"
        } else {
            Add-LogMessage -Level Fatal "NIC removal failed!"
        }
    }

    # Remove the existing disks
    # -------------------------
    $diskNames = @("OS", "SCRATCH", "HOME")
    foreach ($diskName in $diskNames) {
        Add-LogMessage -Level Info "[ ] Removing '$diskName' disk"
        $disk = Get-AzDisk | Where-Object { $_.Name -match "$vmNamePrefix-\d-\d-\d{10}-$diskName-DISK" }
        if ($disk) {
            if ($disk.Length -ne 1) {
                Add-LogMessage -Level Warning "Multiple candidate '$diskName' disks found, not removing any"
            } else {
                $null = Remove-AzDisk -Name $disk.Name -ResourceGroupName $config.sre.dsvm.rg -Force
                if ($?) {
                    Add-LogMessage -Level Success "Disk deletion succeeded"
                } else {
                    Add-LogMessage -Level Fatal "Disk deletion failed!"
                }
            }
        } else {
            Add-LogMessage -Level Success "No disk found"
        }
    }
}


# Check that this is a valid image version and get its ID
# -------------------------------------------------------
$imageDefinition = Get-ImageDefinition -Type $config.sre.dsvm.vmImage.type
$image = Get-ImageFromGallery -ImageVersion $config.sre.dsvm.vmImage.version -ImageDefinition $imageDefinition -GalleryName $config.sre.dsvm.vmImage.gallery -ResourceGroup $config.sre.dsvm.vmImage.rg -Subscription $config.sre.dsvm.vmImage.subscription


# Set the OS disk size for this image
# -----------------------------------
$osDiskSizeGB = $config.sre.dsvm.disks.os.sizeGb
if ($osDiskSizeGB -eq "default") { $osDiskSizeGB = $image.StorageProfile.OsDiskImage.SizeInGB }
if ([int]$osDiskSizeGB -lt [int]$image.StorageProfile.OsDiskImage.SizeInGB) {
    Add-LogMessage -Level Fatal "Image $($image.Name) needs an OS disk of at least $($image.StorageProfile.OsDiskImage.SizeInGB) GB!"
}


# Check for any orphaned disks
# ----------------------------
$orphanedDisks = Get-AzDisk | Where-Object { $_.DiskState -eq "Unattached" } | Where-Object { $_.Name -Like "${$vmNamePrefix}*" }
if ($orphanedDisks) {
    Add-LogMessage -Level Info "Removing $($orphanedDisks.Length) orphaned disks"
    $null = $orphanedDisks | Remove-AzDisk -Force
    if ($?) {
        Add-LogMessage -Level Success "Orphaned disk removal succeeded"
    } else {
        Add-LogMessage -Level Fatal "Orphaned disk removal failed!"
    }
}


# Create DSVM resource group if it does not exist
# ----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.dsvm.rg -Location $config.sre.location


# Retrieve VNET and subnets
# -------------------------
Add-LogMessage -Level Info "Retrieving virtual network '$($config.sre.network.vnet.name)'..."
$vnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
$computeSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.compute.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg
$deploymentSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.deployment.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg


# Set mirror URLs
# ---------------
Add-LogMessage -Level Info "Determining correct URLs for package mirrors..."
$IPs = Get-MirrorIPs $config
$addresses = Get-MirrorAddresses -cranIp $IPs.cran -pypiIp $IPs.pypi -nexus $config.sre.nexus
$success = $?
Add-LogMessage -Level Info "CRAN: '$($addresses.cran.url)'"
Add-LogMessage -Level Info "PyPI: '$($addresses.pypi.index)'"
if ($success) {
    Add-LogMessage -Level Success "Successfully loaded package mirror URLs"
} else {
    Add-LogMessage -Level Fatal "Failed to load package mirror URLs!"
}


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dataMountPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.datamount.passwordSecretName -DefaultLength 20 -AsPlaintext
$domainJoinPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.linuxServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$ingressContainerSasToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers.ingress.connectionSecretName -AsPlaintext
$egressContainerSasToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers.egress.connectionSecretName -AsPlaintext
$ldapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext


# Get deployment and final IP addresses
# -------------------------------------
$deploymentIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.deployment.cidr -VirtualNetwork $vnet
$finalIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.compute.cidr -Offset $ipLastOctet


# Construct the cloud-init YAML file for the target subscription
# --------------------------------------------------------------
Add-LogMessage -Level Info "Constructing cloud-init from template..."
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
$cloudInitFilePath = Get-ChildItem -Path $cloudInitBasePath | Where-Object { $_.Name -eq "cloud-init-compute-vm-sre-${sreId}.template.yaml" } | ForEach-Object { $_.FullName }
if (-not $cloudInitFilePath) { $cloudInitFilePath = Join-Path $cloudInitBasePath "cloud-init-compute-vm.template.yaml" }
$cloudInitTemplate = Get-Content $cloudInitFilePath -Raw

# Insert additional files into the cloud-init template
foreach ($resource in (Get-ChildItem (Join-Path $PSScriptRoot ".." "cloud_init" "resources"))) {
    $indent = $cloudInitTemplate -split "`n" | Where-Object { $_ -match "<$($resource.Name)>" } | ForEach-Object { $_.Split("<")[0] } | Select-Object -First 1
    $indentedContent = (Get-Content $resource.FullName -Raw) -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
    $cloudInitTemplate = $cloudInitTemplate.Replace("${indent}<$($resource.Name)>", $indentedContent)
}

# Insert xrdp logo into the cloud-init template
# Please note that the logo has to be an 8-bit RGB .bmp with no alpha.
# If you want to use a size other than the default (240x140) the xrdp.ini will need to be modified appropriately
$xrdpCustomLogo = Get-Content (Join-Path $PSScriptRoot ".." "cloud_init" "resources" "xrdp_custom_logo.bmp") -Raw -AsByteStream
$outputStream = New-Object IO.MemoryStream
$gzipStream = New-Object System.IO.Compression.GZipStream($outputStream, [Io.Compression.CompressionMode]::Compress)
$gzipStream.Write($xrdpCustomLogo, 0, $xrdpCustomLogo.Length)
$gzipStream.Close()
$xrdpCustomLogoEncoded = [Convert]::ToBase64String($outputStream.ToArray())
$outputStream.Close()
$cloudInitTemplate = $cloudInitTemplate.Replace("<xrdpCustomLogoEncoded>", $xrdpCustomLogoEncoded)

# Expand placeholders in the cloud-init template
$cloudInitTemplate = $cloudInitTemplate.
    Replace("<datamount-password>", $dataMountPassword).
    Replace("<datamount-username>", $config.sre.users.serviceAccounts.datamount.samAccountName).
    Replace("<dataserver-hostname>", $config.sre.dataserver.hostname).
    Replace("<domain-join-password>", $domainJoinPassword).
    Replace("<domain-join-username>", $config.shm.users.computerManagers.linuxServers.samAccountName).
    Replace("<ldap-sre-user-filter>", "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path)))").
    Replace("<ldap-search-user-dn>", "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)").
    Replace("<ldap-search-user-password>", $ldapSearchPassword).
    Replace("<mirror-index-pypi>", $addresses.pypi.index).
    Replace("<mirror-index-url-pypi>", $addresses.pypi.indexUrl).
    Replace("<mirror-host-pypi>", $addresses.pypi.host).
    Replace("<mirror-url-cran>", $addresses.cran.url).
    Replace("<ntp-server>", $config.shm.time.ntp.poolFqdn).
    Replace("<ou-linux-servers-path>", $config.shm.domain.ous.linuxServers.path).
    Replace("<ou-research-users-path>", $config.shm.domain.ous.researchUsers.path).
    Replace("<ou-service-accounts-path>", $config.shm.domain.ous.serviceAccounts.path).
    Replace("<storage-account-persistentdata-name>", $config.sre.storage.persistentdata.account.name).
    Replace("<storage-account-persistentdata-ingress-sastoken>", $ingressContainerSasToken).
    Replace("<storage-account-persistentdata-egress-sastoken>", $egressContainerSasToken).
    Replace("<storage-account-userdata-name>", $config.sre.storage.userdata.account.name).
    Replace("<shm-dc-hostname-lower>", $($config.shm.dc.hostname).ToLower()).
    Replace("<shm-dc-hostname-upper>", $($config.shm.dc.hostname).ToUpper()).
    Replace("<shm-fqdn-lower>", $($config.shm.domain.fqdn).ToLower()).
    Replace("<shm-fqdn-upper>", $($config.shm.domain.fqdn).ToUpper()).
    Replace("<timezone>", $config.sre.time.timezone.linux).
    Replace("<vm-hostname>", $vmName).
    Replace("<vm-ipaddress>", $finalIpAddress)


# Deploy data disks
# -----------------
if ($upgrade) {
    $dataDisks = @()
    for ($i = 0; $i -lt $dataDiskNames.Length; $i++) {
        # Create disk from snapshot
        $diskConfig = New-AzDiskConfig -Location $config.sre.location -SourceResourceId $snapshots[$i].Id -CreateOption Copy
        $diskName = $vmName + "-" + $dataDiskNames[$i] + "-DISK"
        Add-LogMessage -Level Info "[ ] Creating new disk '$diskName'"
        $disk = New-AzDisk -Disk $diskConfig -ResourceGroupName $config.sre.dsvm.rg -DiskName $diskName
        if ($disk) {
            Add-LogMessage -Level Success "Disk creation succeeded"
        } else {
            Add-LogMessage -Level Fatal "Disk creation failed!"
        }
        $dataDisks += $disk
    }
    $scratchDisk = $dataDisks[0]
    $homeDisk = $dataDisks[1]
} else {
    # Create empty disks
    $scratchDisk = Deploy-ManagedDisk -Name "$vmName-SCRATCH-DISK" -SizeGB $config.sre.dsvm.disks.scratch.sizeGb -Type $config.sre.dsvm.disks.scratch.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location
    $homeDisk = Deploy-ManagedDisk -Name "$vmName-HOME-DISK" -SizeGB $config.sre.dsvm.disks.home.sizeGb -Type $config.sre.dsvm.disks.home.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location
}

# Deploy the VM
# -------------
$networkCard = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $deploymentSubnet -PrivateIpAddress $deploymentIpAddress -Location $config.sre.location
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$params = @{
    Name                   = $vmName
    Size                   = $vmSize
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.dsvm.adminPasswordSecretName -DefaultLength 20)
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitTemplate
    location               = $config.sre.location
    NicId                  = $networkCard.Id
    OsDiskSizeGb           = $osDiskSizeGB
    OsDiskType             = $config.sre.dsvm.disks.os.type
    ResourceGroupName      = $config.sre.dsvm.rg
    DataDiskIds            = @($homeDisk.Id, $scratchDisk.Id)
    ImageId                = $image.Id
}
$null = Deploy-UbuntuVirtualMachine @params


# Change subnets and IP address while the VM is off
# -------------------------------------------------
$networkCard.IpConfigurations[0].Subnet.Id = $computeSubnet.Id
$networkCard.IpConfigurations[0].PrivateIpAddress = $finalIpAddress
$null = $networkCard | Set-AzNetworkInterface

# Restart after the networking switch
# -----------------------------------
Enable-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg
# Start-Sleep 60 # we need to allow time for the domain join to run on reboot


# Remove snapshots
# ----------------
if ($upgrade) {
    foreach ($snapshotName in $snapshotNames) {
        Add-LogMessage -Level Info "[ ] Deleting snapshot '$snapshotName'"
        $null = Remove-AzSnapshot -ResourceGroupName $config.sre.dsvm.rg -SnapshotName $snapshotName -Force
        if ($?) {
            Add-LogMessage -Level Success "Snapshot deletion succeeded"
        } else {
            Add-LogMessage -Level Failure "Snapshot deletion failed!"
        }
    }
}


# Create local zip file
# ---------------------
Add-LogMessage -Level Info "Creating smoke test package for the DSVM..."
$zipFilePath = Join-Path $PSScriptRoot "smoke_tests.zip"
$tempDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()) "smoke_tests")
Copy-Item (Join-Path $PSScriptRoot ".." ".." "dsvm_images" "packages") -Filter *.* -Destination (Join-Path $tempDir package_lists) -Recurse
Copy-Item (Join-Path $PSScriptRoot ".." "remote" "compute_vm" "tests") -Filter *.* -Destination (Join-Path $tempDir tests) -Recurse
# Set correct database paths
$template = Join-Path $PSScriptRoot ".." "remote" "compute_vm" "tests" "test_databases.sh" | Get-Item | Get-Content -Raw
$template.Replace("<mssql-port>", $config.sre.databases.dbmssql.port).
          Replace("<mssql-server-name>", "$($config.sre.databases.dbmssql.vmName).$($config.shm.domain.fqdn)").
          Replace("<postgres-port>", $config.sre.databases.dbpostgresql.port).
          Replace("<postgres-server-name>", "$($config.sre.databases.dbpostgresql.vmName).$($config.shm.domain.fqdn)") | Set-Content -Path (Join-Path $tempDir "tests" "test_databases.sh")
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
}
Add-LogMessage -Level Info "[ ] Uploading and extracting smoke tests on $vmName"
$null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params


# Run remote diagnostic scripts
# -----------------------------
Invoke-Expression -Command "$(Join-Path $PSScriptRoot 'Run_SRE_DSVM_Remote_Diagnostics.ps1') -configId $configId -ipLastOctet $ipLastOctet"


# Get private IP address for this machine
# ---------------------------------------
$privateIpAddress = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg).Id } | ForEach-Object { $_.IpConfigurations.PrivateIpAddress }
Add-LogMessage -Level Info "Deployment complete. This new VM can be accessed from the RDS at $privateIpAddress"


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
