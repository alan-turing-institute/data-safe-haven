param(
    [Parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter SRE config ID. This will be the concatenation of <SHM ID> and <SRE ID> (eg. 'testasandbox' for SRE 'sandbox' in SHM 'testa')")]
    [string]$configId,
    [Parameter(Position = 1, Mandatory = $true, HelpMessage = "Last octet of IP address eg. '160'")]
    [string]$ipLastOctet = (Read-Host -Prompt "Last octet of IP address eg. '160'"),
    [Parameter(Position = 2, Mandatory = $false, HelpMessage = "Enter VM size to use (or leave empty to use default)")]
    [string]$vmSize = "",
    [Parameter(Position = 3, Mandatory = $false, HelpMessage = "Perform an in-place upgrade.")]
    [switch]$Upgrade,
    [Parameter(Position = 4, Mandatory = $false, HelpMessage = "Force an in-place upgrade.")]
    [switch]$Force
)

Import-Module Az -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
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
# We need to define a unique hostname of no more than 15 characters
# -----------------------------------------------------------------
if (!$vmSize) { $vmSize = $config.sre.dsvm.vmSizeDefault }
$vmHostname = "SRE-$($config.sre.id)-${ipLastOctet}".ToUpper()
$vmNamePrefix = "${vmHostname}-DSVM".ToUpper()
$vmName = "$vmNamePrefix-$($config.sre.dsvm.vmImage.version)".Replace(".", "-")


# Create DSVM resource group if it does not exist
# ----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.dsvm.rg -Location $config.sre.location


# Retrieve VNET and subnets
# -------------------------
Add-LogMessage -Level Info "Retrieving virtual network '$($config.sre.network.vnet.name)'..."
$vnet = Get-AzVirtualNetwork -Name $config.sre.network.vnet.name -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
$computeSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.compute.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg
$deploymentSubnet = Get-Subnet -Name $config.sre.network.vnet.subnets.deployment.name -VirtualNetworkName $vnet.Name -ResourceGroupName $config.sre.network.vnet.rg


# Get deployment and final IP addresses
# -------------------------------------
$deploymentIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.deployment.cidr -VirtualNetwork $vnet
$finalIpAddress = Get-NextAvailableIpInRange -IpRangeCidr $config.sre.network.vnet.subnets.compute.cidr -Offset $ipLastOctet


# Check whether this IP address has been used.
# --------------------------------------------
$existingNic = Get-AzNetworkInterface | Where-Object { $_.IpConfigurations.PrivateIpAddress -eq $finalIpAddress }
if (($existingNic.VirtualMachine.Id) -and -not $Upgrade) {
    Add-LogMessage -Level InfoSuccess "A VM already exists with IP address '$finalIpAddress'. Use -Upgrade if you want to overwrite this."
    $null = Set-AzContext -Context $originalContext -ErrorAction Stop
    exit 0
}


# If we are upgrading then we need an existing VM
# -----------------------------------------------
if ($Upgrade) {
    # Attempt to find exactly one existing virtual machine
    $existingVm = Get-AzVM | Where-Object { $_.Name -match "$vmNamePrefix-\d-\d-\d{10}" }
    if (-not $existingVm) {
        Add-LogMessage -Level Fatal "No existing VM found to upgrade"
    } elseif ($existingVm.Length -ne 1) {
        $existingVm | ForEach-Object { Add-LogMessage -Level Info "Candidate VM: '$($_.Name)'" }
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
        Add-LogMessage -Level Fatal "Multiple candidate VMs found, aborting upgrade"
    } else {
        Add-LogMessage -Level Info "Found an existing VM '$($existingVm.Name)'"
    }

    # Check whether an upgrade is needed
    if (($existingVm.Name -eq $vmName) -and -not $Force) {
        Add-LogMessage -Level Warning "The existing VM appears to be using the same image version, no upgrade is needed. Use -Force to upgrade anyway."
        $null = Set-AzContext -Context $originalContext -ErrorAction Stop
        exit 0
    }

    # Stop and remove the existing VM
    Stop-VM -Name $existingVm.Name -ResourceGroupName $existingVm.ResourceGroupName
    Add-LogMessage -Level Info "[ ] Removing existing VM '$($existingVm.Name)'"
    $null = Remove-VirtualMachine -Name $existingVm.Name -ResourceGroupName $existingVm.ResourceGroupName -Force
    if ($?) {
        Add-LogMessage -Level Success "Removal of VM '$($existingVm.Name)' succeeded"
    } else {
        Add-LogMessage -Level Fatal "Removal of VM '$($existingVm.Name)' failed!"
    }

    # Remove the existing NIC
    if ($existingNic) {
        Add-LogMessage -Level Info "[ ] Deleting existing network card '$($existingNic.Name)'"
        $null = Remove-AzNetworkInterface -Name $existingNic.Name -ResourceGroupName $existingNic.ResourceGroupName -Force
        if ($?) {
            Add-LogMessage -Level Success "Removal of network card '$($existingNic.Name)' succeeded"
        } else {
            Add-LogMessage -Level Fatal "Removal of network card '$($existingNic.Name)' failed!"
        }
    }

    # Remove the existing disks
    foreach ($diskType in @("OS")) {
        Add-LogMessage -Level Info "[ ] Removing '$diskType' disks"
        foreach ($disk in $(Get-AzDisk | Where-Object { $_.Name -match "$vmNamePrefix-\d-\d-\d{10}-$diskType-DISK" })) {
            $null = $disk | Remove-AzDisk -Force
            if ($?) {
                Add-LogMessage -Level Success "Removal of '$($disk.Name)' succeeded"
            } else {
                Add-LogMessage -Level Fatal "Removal of '$($disk.Name)' failed!"
            }
        }
    }
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


# Set mirror URLs
# ---------------
Add-LogMessage -Level Info "Determining correct URLs for package mirrors..."
$IPs = Get-MirrorIPs $config
$addresses = Get-MirrorAddresses -cranIp $IPs.cran -pypiIp $IPs.pypi -nexus $config.sre.nexus
if ($?) {
    Add-LogMessage -Level Info "CRAN: '$($addresses.cran.url)'"
    Add-LogMessage -Level Info "PyPI: '$($addresses.pypi.index)'"
    Add-LogMessage -Level Success "Successfully loaded package mirror URLs"
} else {
    Add-LogMessage -Level Fatal "Failed to load package mirror URLs!"
}


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$domainJoinPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.linuxServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$ingressContainerSasToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers.ingress.connectionSecretName -AsPlaintext
$egressContainerSasToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers.egress.connectionSecretName -AsPlaintext
$ldapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext


# Construct the cloud-init YAML file for the target subscription
# --------------------------------------------------------------
Add-LogMessage -Level Info "Constructing cloud-init from template..."
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
$cloudInitFilePath = Get-ChildItem -Path $cloudInitBasePath | Where-Object { $_.Name -eq "cloud-init-compute-vm-sre-${sreId}.template.yaml" } | ForEach-Object { $_.FullName }
if (-not $cloudInitFilePath) { $cloudInitFilePath = Join-Path $cloudInitBasePath "cloud-init-compute-vm.template.yaml" }

# Insert resources into the cloud-init template
$cloudInitTemplate = Get-Content $cloudInitFilePath -Raw
foreach ($resource in (Get-ChildItem (Join-Path $cloudInitBasePath "resources"))) {
    $indent = $cloudInitTemplate -split "`n" | Where-Object { $_ -match "<$($resource.Name)>" } | ForEach-Object { $_.Split("<")[0] } | Select-Object -First 1
    $indentedContent = (Get-Content $resource.FullName -Raw) -split "`n" | ForEach-Object { "${indent}$_" } | Join-String -Separator "`n"
    $cloudInitTemplate = $cloudInitTemplate.Replace("${indent}<$($resource.Name)>", $indentedContent)
}

# Insert xrdp logo into the cloud-init template
# Please note that the logo has to be an 8-bit RGB .bmp with no alpha.
# If you want to use a size other than the default (240x140) the xrdp.ini will need to be modified appropriately
$xrdpCustomLogo = Get-Content (Join-Path $cloudInitBasePath "resources" "xrdp_custom_logo.bmp") -Raw -AsByteStream
$outputStream = New-Object IO.MemoryStream
$gzipStream = New-Object System.IO.Compression.GZipStream($outputStream, [Io.Compression.CompressionMode]::Compress)
$gzipStream.Write($xrdpCustomLogo, 0, $xrdpCustomLogo.Length)
$gzipStream.Close()
$xrdpCustomLogoEncoded = [Convert]::ToBase64String($outputStream.ToArray())
$outputStream.Close()
$cloudInitTemplate = $cloudInitTemplate.Replace("<xrdpCustomLogoEncoded>", $xrdpCustomLogoEncoded)

# Expand placeholders in the cloud-init template
$cloudInitTemplate = $cloudInitTemplate.
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
    Replace("<vm-hostname>", ($vmHostname | Limit-StringLength -MaximumLength 15)).
    Replace("<vm-ipaddress>", $finalIpAddress)


# Deploy the VM
# -------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$networkCard = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $deploymentSubnet -PrivateIpAddress $deploymentIpAddress -Location $config.sre.location
$dataDisks = @(
    (Deploy-ManagedDisk -Name "$vmName-SCRATCH-DISK" -SizeGB $config.sre.dsvm.disks.scratch.sizeGb -Type $config.sre.dsvm.disks.scratch.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location)
)
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
    DataDiskIds            = ($dataDisks | ForEach-Object { $_.Id })
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
Start-VM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg
Wait-For -Target "domain joining to complete" -Seconds 120


# Upload smoke tests to DSVM
# --------------------------
Add-LogMessage -Level Info "Creating smoke test package for the DSVM..."
# Arrange files in temporary directory
$localSmokeTestDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()) "smoke_tests")
Copy-Item (Join-Path $PSScriptRoot ".." ".." "dsvm_images" "packages") -Filter *.* -Destination (Join-Path $localSmokeTestDir package_lists) -Recurse
Copy-Item (Join-Path $PSScriptRoot ".." "remote" "compute_vm" "tests") -Filter *.* -Destination (Join-Path $localSmokeTestDir tests) -Recurse
$template = Join-Path $localSmokeTestDir "tests" "test_databases.sh" | Get-Item | Get-Content -Raw
$template.Replace("<mssql-port>", $config.sre.databases.dbmssql.port).
          Replace("<mssql-server-name>", "$($config.sre.databases.dbmssql.vmName).$($config.shm.domain.fqdn)").
          Replace("<postgres-port>", $config.sre.databases.dbpostgresql.port).
          Replace("<postgres-server-name>", "$($config.sre.databases.dbpostgresql.vmName).$($config.shm.domain.fqdn)") | Set-Content -Path (Join-Path $localSmokeTestDir "tests" "test_databases.sh")
Move-Item -Path (Join-Path $localSmokeTestDir "tests" "run_all_tests.bats") -Destination $localSmokeTestDir
# Upload files to VM via the SHM persistent data storage account (since access is allowed from both the deployment machine and the DSVM)
$persistentStorageAccount = Get-StorageAccount -Name $config.sre.storage.persistentdata.account.name -ResourceGroupName $config.shm.storage.persistentdata.rg -SubscriptionName $config.shm.subscriptionName -ErrorAction Stop
Send-FilesToLinuxVM -LocalDirectory $localSmokeTestDir -RemoteDirectory "/opt/verification" -VMName $vmName -VMResourceGroupName $config.sre.dsvm.rg -BlobStorageAccount $persistentStorageAccount
Remove-Item -Path $localSmokeTestDir -Recurse -Force
# Set smoke test permissions
Add-LogMessage -Level Info "[ ] Set smoke test permissions on $vmName"
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "compute_vm" "scripts" "set_smoke_test_permissions.sh"
$null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg


# Run remote diagnostic scripts
# -----------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Run_SRE_DSVM_Remote_Diagnostics.ps1')" -configId $configId -ipLastOctet $ipLastOctet }


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
