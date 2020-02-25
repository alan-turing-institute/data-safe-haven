param(
    [Parameter(Position = 0,Mandatory = $true,HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
    [string]$sreId,
    [Parameter(Position = 1,Mandatory = $true,HelpMessage = "Last octet of IP address eg. '160'")]
    [string]$ipLastOctet = (Read-Host -Prompt "Last octet of IP address eg. '160'"),
    [Parameter(Position = 2,Mandatory = $false,HelpMessage = "Enter VM size to use (or leave empty to use default)")]
    [string]$vmSize = "" #(Read-Host -prompt "Enter VM size to use (or leave empty to use default)")
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Logging.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Mirrors.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force


# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-SreConfig $sreId
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.sre.subscriptionName


# Set common variables
# --------------------
$vnetName = $config.sre.network.vnet.Name
$subnetName = $config.sre.network.subnets.data.Name


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dsvmLdapPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmLdapPassword
$dsvmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmAdminPassword
$dsvmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$dsvmDbAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmDbAdminPassword
$dsvmDbReaderPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmDbReaderPassword
$dsvmDbWriterPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.Name -SecretName $config.sre.keyVault.secretNames.dsvmDbWriterPassword


# Get list of image versions
# --------------------------
Add-LogMessage -Level Info "Getting image type from gallery..."
$_ = Set-AzContext -Subscription $config.sre.dsvm.vmImageSubscription
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


# Create DSVM resource group if it does not exist
# ----------------------------------------------
$_ = Set-AzContext -Subscription $config.sre.subscriptionName
$_ = Deploy-ResourceGroup -Name $config.sre.dsvm.rg -Location $config.sre.location


# Set up the NSG for the webapps
# ------------------------------
$secureNsg = Deploy-NetworkSecurityGroup -Name $config.sre.dsvm.nsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $secureNsg `
                             -Name "OutboundDenyInternet" `
                             -Description "Outbound deny internet" `
                             -Priority 4000 `
                             -Direction Outbound -Access Deny -Protocol * `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix Internet -DestinationPortRange *


# Check that deployment NSG exists
# --------------------------------
$deploymentNsg = Deploy-NetworkSecurityGroup -Name $config.sre.dsvm.deploymentNsg -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
$shmIdentitySubnetIpRange = $config.shm.network.subnets.identity.cidr
# Inbound: allow LDAP then deny all
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $deploymentNsg `
                             -Name "InboundAllowLDAP" `
                             -Description "Inbound allow LDAP" `
                             -Priority 2000 `
                             -Direction Inbound -Access Allow -Protocol * `
                             -SourceAddressPrefix $shmIdentitySubnetIpRange -SourcePortRange 88,389,636 `
                             -DestinationAddressPrefix VirtualNetwork -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $deploymentNsg `
                             -Name "InboundDenyAll" `
                             -Description "Inbound deny all" `
                             -Priority 3000 `
                             -Direction Inbound -Access Deny -Protocol * `
                             -SourceAddressPrefix * -SourcePortRange * `
                             -DestinationAddressPrefix * -DestinationPortRange *
# Outbound: allow LDAP then deny all Virtual Network
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $deploymentNsg `
                             -Name "OutboundAllowLDAP" `
                             -Description "Outbound allow LDAP" `
                             -Priority 2000 `
                             -Direction Outbound -Access Allow -Protocol * `
                             -SourceAddressPrefix VirtualNetwork -SourcePortRange * `
                             -DestinationAddressPrefix $shmIdentitySubnetIpRange -DestinationPortRange *
Add-NetworkSecurityGroupRule -NetworkSecurityGroup $deploymentNsg `
                             -Name "OutboundDenyVNet" `
                             -Description "Outbound deny virtual network" `
                             -Priority 3000 `
                             -Direction Outbound -Access Deny -Protocol * `
                             -SourceAddressPrefix * -SourcePortRange * `
                             -DestinationAddressPrefix VirtualNetwork -DestinationPortRange *


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

Add-LogMessage -Level Info "Looking for subnet network '$subnetName'..."
$subnet = $vnet.subnets | Where-Object { $_.Name -eq $subnetName }
if ($null -eq $subnet) {
    Add-LogMessage -Level Fatal "Subnet '$subnetName' could not be found in virtual network '$($vnet.Name)'!"
}
Add-LogMessage -Level Success "Found subnet '$($subnet.Name)' in $($vnet.Name)"


# Set mirror URLs
# ---------------
Add-LogMessage -Level Info "Determining correct URLs for package mirrors..."
$addresses = Get-MirrorAddresses -cranIp $config.sre.mirrors.cran.ip -pypiIp $config.sre.mirrors.pypi.ip
Add-LogMessage -Level Success "CRAN: '$($addresses.cran.url)'"
Add-LogMessage -Level Success "PyPI server: '$($addresses.pypi.url)'"
Add-LogMessage -Level Success "PyPI host: '$($addresses.pypi.host)'"


# Construct the cloud-init yaml file for the target subscription
# --------------------------------------------------------------
Add-LogMessage -Level Info "Constructing cloud-init from template..."
# Load cloud-init template
$cloudInitBasePath = Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "cloud_init" -Resolve
$cloudInitFilePath = Get-ChildItem -Path $cloudInitBasePath | Where-Object { $_.Name -eq "cloud-init-compute-vm-sre-${sreId}.template.yaml" } | ForEach-Object { $_.FullName }
if (-not $cloudInitFilePath) { $cloudInitFilePath = Join-Path $cloudInitBasePath "cloud-init-compute-vm.template.yaml" }
$cloudInitTemplate = Get-Content $cloudInitFilePath -Raw
# Set template expansion variables
$LDAP_SECRET_PLAINTEXT = $dsvmLdapPassword
$DOMAIN_UPPER = $($config.shm.domain.fqdn).ToUpper()
$DOMAIN_LOWER = $($DOMAIN_UPPER).ToLower()
$AD_DC_NAME_UPPER = $($config.shm.dc.hostname).ToUpper()
$AD_DC_NAME_LOWER = $($AD_DC_NAME_UPPER).ToLower()
$ADMIN_USERNAME = $dsvmAdminUsername
$MACHINE_NAME = $vmName
$LDAP_USER = $config.sre.users.ldap.dsvm.samAccountName
$LDAP_BASE_DN = $config.shm.domain.userOuPath
$LDAP_BIND_DN = "CN=" + $config.sre.users.ldap.dsvm.Name + "," + $config.shm.domain.serviceOuPath
$LDAP_FILTER = "(&(objectClass=user)(memberOf=CN=" + $config.sre.domain.securityGroups.researchUsers.Name + "," + $config.shm.domain.securityOuPath + "))"
$CRAN_MIRROR_URL = $addresses.cran.url
$PYPI_MIRROR_URL = $addresses.pypi.url
$PYPI_MIRROR_HOST = $addresses.pypi.host
$cloudInitYaml = $ExecutionContext.InvokeCommand.ExpandString($cloudInitTemplate)


# Get some default VM names
# -------------------------
# Set default VM size if no argument is provided
if (!$vmSize) { $vmSize = $config.sre.dsvm.vmSizeDefault }
# Set IP address using last IP octet
$vmIpAddress = $config.sre.network.subnets.data.prefix + "." + $ipLastOctet
# Set machine name using last IP octet
$vmName = "DSVM-" + ($imageVersion).Replace(".","-").ToUpper() + "-SRE-" + ($config.sre.Id).ToUpper() + "-" + $ipLastOctet

# Deploy NIC and data disks
# -------------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.storage.bootdiagnostics.accountName -ResourceGroupName $config.sre.storage.bootdiagnostics.rg -Location $config.sre.location
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $subnet -PrivateIpAddress $vmIpAddress -Location $config.sre.location
$dataDisk = Deploy-ManagedDisk -Name "$vmName-DATA-DISK" -SizeGB $config.sre.dsvm.datadisk.size_gb -Type $config.sre.dsvm.datadisk.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location
$homeDisk = Deploy-ManagedDisk -Name "$vmName-HOME-DISK" -SizeGB $config.sre.dsvm.homedisk.size_gb -Type $config.sre.dsvm.homedisk.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location

# Deploy the VM
# -------------
$params = @{
    Name = $vmName
    Size = $vmSize
    AdminPassword = $dsvmAdminPassword
    AdminUsername = $dsvmAdminUsername
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    CloudInitYaml = $cloudInitYaml
    location = $config.sre.location
    NicId = $vmNic.Id
    OsDiskType = $config.sre.dsvm.osdisk.type
    ResourceGroupName = $config.sre.dsvm.rg
    DataDiskIds = @($dataDisk.Id,$homeDisk.Id)
    ImageId = $image.Id
}
$_ = Deploy-UbuntuVirtualMachine @params


# Poll VM to see whether it has finished running
Add-LogMessage -Level Info "Waiting for cloud-init provisioning to finish (this will take 5+ minutes)..."
$statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg -Status).Statuses.Code
$progress = 0
while (-not ($statuses.Contains("PowerState/stopped") -and $statuses.Contains("ProvisioningState/succeeded"))) {
    $statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg -Status).Statuses.Code
    $progress += 1
    Write-Progress -Activity "Deployment status" -Status "$($statuses[0]) $($statuses[1])" -PercentComplete $progress
    Start-Sleep 10
}


# VM must be off for us to switch NSG, but we can restart after the switch
# ------------------------------------------------------------------------
Add-LogMessage -Level Info "Switching to secure NSG '$($secureNsg.Name)' at $(Get-Date -UFormat '%d-%b-%Y %R')..."
Add-VmToNSG -VMName $vmName -NSGName $secureNsg.Name
$_ = Start-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg


# Create Postgres roles
# ---------------------
Add-LogMessage -Level Info "[ ] Ensuring Postgres DB roles and initial shared users exist on VM $vmName"
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "create_postgres_roles.sh"
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
Copy-Item (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists") -Filter *.* -Destination (Join-Path $tempDir package_lists) -Recurse
Copy-Item (Join-Path $PSScriptRoot ".." ".." ".." "vm_image_management" "tests") -Filter *.* -Destination (Join-Path $tempDir tests) -Recurse
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
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "upload_smoke_tests.sh"
$params = @{
    PAYLOAD = $zipFileEncoded
    ADMIN_USERNAME = $dsvmAdminUsername
};
Add-LogMessage -Level Info "[ ] Uploading and extracting smoke tests on $vmName"
$result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
Write-Output $result.Value


# Get private IP address for this machine
# ---------------------------------------
$privateIpAddress = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg).Id } | ForEach-Object { $_.IpConfigurations.PrivateIpAddress }
Add-LogMessage -Level Info "Deployment complete at $(Get-Date -UFormat '%d-%b-%Y %R')"
Add-LogMessage -Level Info "This new VM can be accessed with SSH or remote desktop at $privateIpAddress"
