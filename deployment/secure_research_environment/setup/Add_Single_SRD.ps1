param(
    [Parameter(Mandatory = $true, HelpMessage = "Enter SHM ID (e.g. use 'testa' for Turing Development Safe Haven A)")]
    [string]$shmId,
    [Parameter(Mandatory = $true, HelpMessage = "Enter SRE ID (e.g. use 'sandbox' for Turing Development Sandbox SREs)")]
    [string]$sreId,
    [Parameter(Mandatory = $true, HelpMessage = "Last octet of IP address (eg. '160')")]
    [string]$ipLastOctet,
    [Parameter(Mandatory = $false, HelpMessage = "Enter VM size to use (or leave empty to use default)")]
    [string]$vmSize = "default",
    [Parameter(Mandatory = $false, HelpMessage = "Perform an in-place upgrade.")]
    [switch]$Upgrade,
    [Parameter(Mandatory = $false, HelpMessage = "Force an in-place upgrade.")]
    [switch]$Force
)

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.Compute -ErrorAction Stop
Import-Module Az.Network -ErrorAction Stop
Import-Module Az.Resources -ErrorAction Stop
Import-Module Powershell-Yaml -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureCompute -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureKeyVault -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureNetwork -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureResources -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/AzureStorage -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Configuration -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Cryptography -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/DataStructures -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Logging -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/RemoteCommands -Force -ErrorAction Stop
Import-Module $PSScriptRoot/../../common/Templates -Force -ErrorAction Stop


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig -shmId $shmId -sreId $sreId
$originalContext = Get-AzContext
$null = Set-AzContext -SubscriptionId $config.sre.subscriptionName -ErrorAction Stop


# Set VM name and size
# We need to define a unique hostname of no more than 15 characters
# -----------------------------------------------------------------
if ($vmSize -eq "default") { $vmSize = $config.sre.srd.vmSizeDefault }
$vmHostname = "SRE-$($config.sre.id)-${ipLastOctet}".ToUpper()
$vmNamePrefix = "${vmHostname}-SRD".ToUpper()
$vmName = "$vmNamePrefix-$($config.sre.srd.vmImage.version)".Replace(".", "-")


# Create SRD resource group if it does not exist
# ----------------------------------------------
$null = Deploy-ResourceGroup -Name $config.sre.srd.rg -Location $config.sre.location


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
$existingNic = Get-AzNetworkInterface -ResourceGroupName $config.sre.srd.rg | Where-Object { $_.IpConfigurations.PrivateIpAddress -eq $finalIpAddress }
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
$image = Get-ImageFromGallery -GalleryName $config.shm.srdImage.gallery.name `
                              -ImageSku $config.sre.srd.vmImage.type `
                              -ImageVersion $config.sre.srd.vmImage.version  `
                              -ResourceGroupName $config.shm.srdImage.gallery.rg `
                              -Subscription $config.shm.srdImage.subscription


# Set the OS disk size for this image
# -----------------------------------
$osDiskSizeGB = $config.sre.srd.disks.os.sizeGb
if ($osDiskSizeGB -eq "default") { $osDiskSizeGB = 2 * [int]($image.StorageProfile.OsDiskImage.SizeInGB) }
if ([int]$osDiskSizeGB -lt [int]$image.StorageProfile.OsDiskImage.SizeInGB) {
    Add-LogMessage -Level Fatal "Image $($image.Name) needs an OS disk of at least $($image.StorageProfile.OsDiskImage.SizeInGB) GB!"
}


# Retrieve passwords from the Key Vault
# -------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from Key Vault '$($config.sre.keyVault.name)'..."
$domainJoinPassword = Resolve-KeyVaultSecret -VaultName $config.shm.keyVault.name -SecretName $config.shm.users.computerManagers.linuxServers.passwordSecretName -DefaultLength 20 -AsPlaintext
$backupContainerSasToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers.backup.connectionSecretName -AsPlaintext
$ingressContainerSasToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers.ingress.connectionSecretName -AsPlaintext
$egressContainerSasToken = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.storage.persistentdata.containers.egress.connectionSecretName -AsPlaintext
$ldapSearchPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.users.serviceAccounts.ldapSearch.passwordSecretName -DefaultLength 20 -AsPlaintext
$vmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.adminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower() -AsPlaintext


# Construct the cloud-init YAML file for the target subscription
# --------------------------------------------------------------
Add-LogMessage -Level Info "Constructing cloud-init from template..."
$cloudInitBasePath = Join-Path $PSScriptRoot ".." "cloud_init" -Resolve
$cloudInitFilePath = Get-ChildItem -Path $cloudInitBasePath | Where-Object { $_.Name -eq "cloud-init-srd-shm-${shmId}-sre-${sreId}.mustache.yaml" } | ForEach-Object { $_.FullName }
if (-not $cloudInitFilePath) { $cloudInitFilePath = Join-Path $cloudInitBasePath "cloud-init-srd.mustache.yaml" }
# Load the cloud-init template then add resources and expand mustache placeholders
$config["srd"] = @{
    domainJoinPassword       = $domainJoinPassword
    ldapUserFilter           = "(&(objectClass=user)(memberOf=CN=$($config.sre.domain.securityGroups.researchUsers.name),$($config.shm.domain.ous.securityGroups.path)))"
    ldapSearchUserDn         = "CN=$($config.sre.users.serviceAccounts.ldapSearch.name),$($config.shm.domain.ous.serviceAccounts.path)"
    ldapSearchUserPassword   = $ldapSearchPassword
    backupContainerSasToken  = $backupContainerSasToken
    ingressContainerSasToken = $ingressContainerSasToken
    egressContainerSasToken  = $egressContainerSasToken
    hostname                 = ($vmHostname | Limit-StringLength -MaximumLength 15)
    ipAddress                = $finalIpAddress
    xrdpCustomLogoEncoded    = (ConvertTo-Base64GZip -Path (Join-Path $cloudInitBasePath "resources" "xrdp_custom_logo.bmp"))
}
$cloudInitTemplate = Get-Content $cloudInitFilePath -Raw
$cloudInitTemplate = Expand-CloudInitResources -Template $cloudInitTemplate -ResourcePath (Join-Path $cloudInitBasePath "resources")
$cloudInitTemplate = Expand-MustacheTemplate -Template $cloudInitTemplate -Parameters $config


# Deploy the VM
# -------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$networkCard = Deploy-NetworkInterface -Name "$vmName-NIC" -ResourceGroupName $config.sre.srd.rg -Subnet $deploymentSubnet -PrivateIpAddress $deploymentIpAddress -Location $config.sre.location
$dataDisks = @(
    (Deploy-ManagedDisk -Name "$vmName-SCRATCH-DISK" -SizeGB $config.sre.srd.disks.scratch.sizeGb -Type $config.sre.srd.disks.scratch.type -ResourceGroupName $config.sre.srd.rg -Location $config.sre.location)
)
$params = @{
    Name                   = $vmName
    Size                   = $vmSize
    AdminPassword          = (Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.srd.adminPasswordSecretName -DefaultLength 20)
    AdminUsername          = $vmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml          = $cloudInitTemplate
    location               = $config.sre.location
    NicId                  = $networkCard.Id
    OsDiskSizeGb           = $osDiskSizeGB
    OsDiskType             = $config.sre.srd.disks.os.type
    ResourceGroupName      = $config.sre.srd.rg
    DataDiskIds            = ($dataDisks | ForEach-Object { $_.Id })
    ImageId                = $image.Id
}
$vm = Deploy-LinuxVirtualMachine @params
$null = New-AzTag -ResourceId $vm.Id -Tag @{"Build commit hash" = $image.Tags["Build commit hash"] }


# Change subnets and IP address while the VM is off
# -------------------------------------------------
Update-VMIpAddress -Name $vmName -ResourceGroupName $config.sre.srd.rg -Subnet $computeSubnet -IpAddress $finalIpAddress
# Update DNS records for this VM
Update-VMDnsRecords -DcName $config.shm.dc.vmName -DcResourceGroupName $config.shm.dc.rg -BaseFqdn $config.shm.domain.fqdn -ShmSubscriptionName $config.shm.subscriptionName -VmHostname $vmHostname -VmIpAddress $finalIpAddress


# Restart after the networking switch
# -----------------------------------
Start-VM -Name $vmName -ResourceGroupName $config.sre.srd.rg
Wait-For -Target "domain joining to complete" -Seconds 120


# Upload smoke tests to SRD
# -------------------------
Add-LogMessage -Level Info "Creating smoke test package for the SRD..."
# Arrange files in temporary directory
$localSmokeTestDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()) "smoke_tests")
Copy-Item (Join-Path $PSScriptRoot ".." ".." "secure_research_desktop" "packages") -Filter *.* -Destination (Join-Path $localSmokeTestDir "package_lists") -Recurse
Copy-Item (Join-Path $PSScriptRoot ".." ".." ".." "tests" "srd_smoke_tests") -Filter *.* -Destination (Join-Path $localSmokeTestDir "tests") -Recurse
# Expand mustache templates
$PythonYaml = (ConvertFrom-Yaml (Get-Content -Raw (Join-Path $PSScriptRoot ".." ".." "secure_research_desktop" "packages" "packages-python.yaml")))
$config["SmokeTests"] = [ordered]@{
    PyPIPackage0 = Get-Content (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "allowlist-full-python-pypi-tier3.list") -Head 1
    PyPIPackage1 = Get-Content (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists" "allowlist-full-python-pypi-tier3.list") -Tail 1
    Python_v0    = $PythonYaml["versions"][0]
    Python_v1    = $PythonYaml["versions"][1]
    Python_v2    = $PythonYaml["versions"][2]
    TestFailures = $config.sre.tier -ge 3 ? 1 : 0
}
foreach ($MustacheFilePath in (Get-ChildItem -Path $localSmokeTestDir -Include *.mustache.* -File -Recurse)) {
    $ExpandedFilePath = $MustacheFilePath -replace ".mustache.", "."
    Expand-MustacheTemplate -TemplatePath $MustacheFilePath -Parameters $config | Set-Content -Path $ExpandedFilePath
    Remove-Item -Path $MustacheFilePath
}
Move-Item -Path (Join-Path $localSmokeTestDir "tests" "run_all_tests.bats") -Destination $localSmokeTestDir
Move-Item -Path (Join-Path $localSmokeTestDir "tests" "README.md") -Destination $localSmokeTestDir
# Upload files to VM via the SRE artifacts storage account (note that this requires access to be allowed from both the deployment machine and the SRD)
$artifactsStorageAccount = Get-StorageAccount -Name $config.sre.storage.artifacts.account.name -ResourceGroupName $config.sre.storage.artifacts.rg -SubscriptionName $config.sre.subscriptionName -ErrorAction Stop
Send-FilesToLinuxVM -LocalDirectory $localSmokeTestDir -RemoteDirectory "/opt/tests" -VMName $vmName -VMResourceGroupName $config.sre.srd.rg -BlobStorageAccount $artifactsStorageAccount
Remove-Item -Path $localSmokeTestDir -Recurse -Force
# Set smoke test permissions
Add-LogMessage -Level Info "[ ] Set smoke test permissions on $vmName"
$scriptPath = Join-Path $PSScriptRoot ".." "remote" "secure_research_desktop" "scripts" "set_smoke_test_permissions.sh"
$null = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.srd.rg


# Run remote diagnostic scripts
# -----------------------------
Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Run_SRE_SRD_Remote_Diagnostics.ps1')" -shmId $shmId -sreId $sreId -ipLastOctet $ipLastOctet }


# Update Guacamole dashboard to include this new VM
# -------------------------------------------------
if ($config.sre.remoteDesktop.provider -eq "ApacheGuacamole") {
    Invoke-Command -ScriptBlock { & "$(Join-Path $PSScriptRoot 'Update_SRE_Guacamole_Dashboard.ps1')" -shmId $shmId -sreId $sreId }
}


# Switch back to original subscription
# ------------------------------------
$null = Set-AzContext -Context $originalContext -ErrorAction Stop
