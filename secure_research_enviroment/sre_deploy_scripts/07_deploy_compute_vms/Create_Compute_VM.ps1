param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (usually a number e.g enter '9' for DSG9)")]
  [string]$sreId,
  [Parameter(Position=1, HelpMessage = "Enter VM size to use (or leave empty to use default)")]
  [string]$vmSize = (Read-Host -prompt "Enter VM size to use (or leave empty to use default)"),
  [Parameter(Position=2, Mandatory = $true, HelpMessage = "Last octet of IP address")]
  [string]$ipLastOctet = (Read-Host -prompt "Last octet of IP address")
)

Import-Module Az
Import-Module $PSScriptRoot/../../../common_powershell/Security.psm1 -Force
Import-Module $PSScriptRoot/../../../common_powershell/Configuration.psm1 -Force


# Get SRE config
# --------------
$config = Get-SreConfig($sreId);
$originalContext = Get-AzContext


# Set common variables
# --------------------
$imagesResourceGroup = "RG_SH_IMAGE_GALLERY"
$imagesGallery = "SAFE_HAVEN_COMPUTE_IMAGES"
$deploymentNsgName = "NSG_IMAGE_DEPLOYMENT"
$secureNsgName = $config.dsg.network.nsg.data.name
$vnetName = $config.dsg.network.vnet.name
$subnetName = $config.dsg.network.subnets.data.name


# Register shared image gallery
# -----------------------------
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;
$galleryFeatureName = "GalleryPreview"
$galleryResourceName = "galleries/images/versions"
Write-Host -ForegroundColor DarkCyan "Ensuring that this subscription has the $galleryFeatureName feature and $galleryResourceName resource enabled (this may take some time)"
$registrationState = (Get-AzProviderFeature -FeatureName $galleryFeatureName -ProviderNamespace Microsoft.Compute).RegistrationState
$resourceProviderState = (Register-AzResourceProvider -ProviderNamespace Microsoft.Compute).RegistrationState
if ($registrationState -eq "NotRegistered") {
    Write-Host -ForegroundColor DarkCyan "Registering shared image gallery feature in this subscription..."
    Register-AzProviderFeature -FeatureName $galleryFeatureName -ProviderNamespace Microsoft.Compute
}
while (($registrationState -ne "Registered") -or ($resourceProviderState -ne "Registered")){
    $registrationState = (Get-AzProviderFeature -FeatureName $galleryFeatureName -ProviderNamespace Microsoft.Compute).RegistrationState
    $resourceProviderState = (Get-AzResourceProvider -ProviderNamespace Microsoft.Compute | Where-Object {$_.ResourceTypes.ResourceTypeName -eq "$galleryResourceName"}) | % { $_.RegistrationState}
    Write-Host "Registration states: $registrationState and $resourceProviderState"
    Start-Sleep 30
}
Write-Host -ForegroundColor DarkGreen " [o] Feature registration succeeded"


# Retrieve passwords from the keyvault
# ------------------------------------
Write-Host -ForegroundColor DarkCyan "Creating/retrieving secrets from '$($config.dsg.keyVault.name)' KeyVault..."
$dsvmLdapPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dsvmLdapPassword
$dsvmAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dsvmAdminPassword
$dsvmAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dsvmAdminUsername -defaultValue "sre$($config.dsg.id)admin".ToLower()
$dsvmDbAdminPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dsvmDbAdminPassword
$dsvmDbReaderPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dsvmDbReaderPassword
$dsvmDbWriterPassword = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dsvmDbWriterPassword


# Get list of image versions
# --------------------------
Write-Host -ForegroundColor DarkCyan "Getting image type from gallery..."
$_ = Set-AzContext -Subscription $config.dsg.dsvm.vmImageSubscription
if ($config.dsg.dsvm.vmImageType -eq "Ubuntu") {
    $imageDefinition = "ComputeVM-Ubuntu1804Base"
} elseif ($config.dsg.dsvm.vmImageType -eq "UbuntuTorch") {
    $imageDefinition = "ComputeVM-UbuntuTorch1804Base"
} elseif ($config.dsg.dsvm.vmImageType -eq "DataScience") {
    $imageDefinition = "ComputeVM-DataScienceBase"
} elseif ($config.dsg.dsvm.vmImageType -eq "DSG") {
    $imageDefinition = "ComputeVM-DsgBase"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Could not interpret $($config.dsg.dsvm.vmImageType) as an image type!"
    throw "Could not interpret $($config.dsg.dsvm.vmImageType) as an image type!"
}
Write-Host -ForegroundColor DarkGreen " [o] Using image type $imageDefinition"


# Check that this is a valid version and then get the image ID
# ------------------------------------------------------------
$imageVersion = $config.dsg.dsvm.vmImageVersion
Write-Host -ForegroundColor DarkCyan "Looking for image $imageDefinition version $imageVersion..."
try {
    $image = Get-AzGalleryImageVersion -ResourceGroup $imagesResourceGroup -GalleryName $imagesGallery -GalleryImageDefinitionName $imageDefinition -GalleryImageVersionName $imageVersion -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    $versions = Get-AzGalleryImageVersion -ResourceGroup $imagesResourceGroup -GalleryName $imagesGallery -GalleryImageDefinitionName $imageDefinition | Sort-Object Name | % {$_.Name} #Select-Object -Last 1
    Write-Host -ForegroundColor DarkRed " [x] Image version '$imageVersion' is invalid. Available versions are: $versions"
    $imageVersion = $versions | Select-Object -Last 1
    $userVersion = Read-Host -Prompt "Enter the version you would like to use (or leave empty to accept the default: '$imageVersion')"
    if ($versions.Contains($userVersion)) {
        $imageVersion = $userVersion
    }
    $image = Get-AzGalleryImageVersion -ResourceGroup $imagesResourceGroup -GalleryName $imagesGallery -GalleryImageDefinitionName $imageDefinition -GalleryImageVersionName $imageVersion -ErrorAction Stop
}
$imageVersion = $image.Name
Write-Host -ForegroundColor DarkGreen " [o] Found image $imageDefinition version $imageVersion in gallery"


# Setup resource group if it does not already exist
# -------------------------------------------------
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName
$_ = New-AzResourceGroup -Name $config.dsg.dsvm.rg -Location $config.dsg.location -Force


# Check that secure NSG exists
# ----------------------------
Write-Host -ForegroundColor DarkCyan "Looking for secure NSG '$secureNsgName'..."
$secureNsg = $null
try {
    $secureNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $config.dsg.network.vnet.rg -Name $secureNsgName  -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    Write-Host -ForegroundColor DarkRed " [x] NSG '$($secureNsgName )' could not be found!"
    throw "NSG '$($secureNsgName )' could not be found!"
}
Write-Host -ForegroundColor DarkGreen " [o] Found secure NSG '$($secureNsg.Name)' in $($secureNsg.ResourceGroupName)"


# Check that deployment NSG exists
# --------------------------------
Write-Host -ForegroundColor DarkCyan "Looking for deployment NSG '$deploymentNsgName'..."
$deploymentNsg = $null
try {
    $deploymentNsg = Get-AzNetworkSecurityGroup -Name $deploymentNsgName -ResourceGroupName $config.dsg.network.vnet.rg -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Network.Common.NetworkCloudException] {
    Write-Host -ForegroundColor DarkCyan "Creating new NSG '$($deploymentNsgName)'"
    $managementSubnetIpRange = $config.shm.network.subnets.identity.cidr
    # Inbound: allow LDAP then deny all
    $ruleInbound1 = New-AzNetworkSecurityRuleConfig -Access "Allow" `
                                                    -Description "Inbound allow LDAP" `
                                                    -DestinationAddressPrefix "VirtualNetwork" `
                                                    -DestinationPortRange "*" `
                                                    -Direction "Inbound" `
                                                    -Name "InboundAllowLDAP" `
                                                    -Priority 2000 `
                                                    -Protocol "*" `
                                                    -SourceAddressPrefix $managementSubnetIpRange `
                                                    -SourcePortRange 88,389,636
    $ruleInbound2 = New-AzNetworkSecurityRuleConfig -Access "Deny" `
                                                    -Description "Inbound deny all" `
                                                    -DestinationAddressPrefix "*" `
                                                    -DestinationPortRange "*" `
                                                    -Direction "Inbound" `
                                                    -Name "InboundDenyAll" `
                                                    -Priority 3000 `
                                                    -Protocol "*" `
                                                    -SourceAddressPrefix "*" `
                                                    -SourcePortRange "*"
    # Outbound: allow LDAP then deny all Virtual Network
    $ruleOutbound1 = New-AzNetworkSecurityRuleConfig -Access "Allow" `
                                                     -Description "Outbound allow LDAP" `
                                                     -DestinationAddressPrefix $managementSubnetIpRange `
                                                     -DestinationPortRange "*" `
                                                     -Direction "Outbound" `
                                                     -Name "OutboundAllowLDAP" `
                                                     -Priority 2000 `
                                                     -Protocol "*" `
                                                     -SourceAddressPrefix "VirtualNetwork" `
                                                     -SourcePortRange "*"
    $ruleOutbound2 = New-AzNetworkSecurityRuleConfig -Access "Deny" `
                                                     -Description "Outbound deny virtual network" `
                                                     -DestinationAddressPrefix "VirtualNetwork" `
                                                     -DestinationPortRange "*" `
                                                     -Direction "Outbound" `
                                                     -Name "OutboundDenyVNet" `
                                                     -Priority 3000 `
                                                     -Protocol "*" `
                                                     -SourceAddressPrefix "*" `
                                                     -SourcePortRange "*"
    # Create deployment NSG
    $deploymentNsg = New-AzNetworkSecurityGroup -Name $deploymentNsgName -ResourceGroupName $config.dsg.network.vnet.rg -Location $config.dsg.location -SecurityRules $ruleInbound1,$ruleInbound2,$ruleOutbound1,$ruleOutbound2
} catch {
    Write-Host $_.Exception.GetType()
}
Write-Host -ForegroundColor DarkGreen " [o] Found deployment NSG '$($deploymentNsg.Name)' in $($deploymentNsg.ResourceGroupName)"


# Check that VNET and subnet exist
# --------------------------------
Write-Host -ForegroundColor DarkCyan "Looking for virtual network '$vnetName'..."
$vnet = $null
try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $config.dsg.network.vnet.rg -Name $vnetName -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    Write-Host -ForegroundColor DarkRed " [x] Virtual network '$vnetName' could not be found!"
    throw "Virtual network '$vnetName' could not be found!"
}
Write-Host -ForegroundColor DarkGreen " [o] Found virtual network '$($vnet.Name)' in $($vnet.ResourceGroupName)"

Write-Host -ForegroundColor DarkCyan "Looking for subnet network '$subnetName'..."
$subnet = $vnet.subnets | Where-Object {$_.Name -eq $subnetName}
if ($subnet -eq $null) {
    Write-Host -ForegroundColor DarkRed " [x] Subnet '$subnetName' could not be found in virtual network '$vnetName'!"
    throw "Subnet '$subnetName' could not be found in virtual network '$vnetName'!"
}
Write-Host -ForegroundColor DarkGreen " [o] Found subnet '$($subnet.Name)' in $($vnet.Name)"


# Set mirror URLs
# ---------------
Write-Host -ForegroundColor DarkCyan "Determining correct URLs for package mirrors..."
if($config.dsg.mirrors.cran.ip) {
    $CRAN_MIRROR_URL = "http://$($config.dsg.mirrors.cran.ip)"
} else {
    $CRAN_MIRROR_URL = "https://cran.r-project.org"
}
if($config.dsg.mirrors.pypi.ip) {
    $PYPI_MIRROR_URL = "http://$($config.dsg.mirrors.pypi.ip):3128"
} else {
    $PYPI_MIRROR_URL = "https://pypi.org"
}
# We want to extract the hostname from PyPI URLs in either of the following forms
# 1. http://10.20.2.20:3128 => 10.20.2.20
# 2. https://pypi.org       => pypi.org
$PYPI_MIRROR_HOST = ""
if ($PYPI_MIRROR_URL -match "https*:\/\/([^:]*)[:0-9]*") { $PYPI_MIRROR_HOST = $Matches[1] }
Write-Host -ForegroundColor DarkGreen " [o] CRAN: '$CRAN_MIRROR_URL'"
Write-Host -ForegroundColor DarkGreen " [o] PyPI server: '$PYPI_MIRROR_URL'"
Write-Host -ForegroundColor DarkGreen " [o] PyPI host: '$PYPI_MIRROR_HOST'"


# Construct the cloud-init yaml file for the target subscription
# --------------------------------------------------------------
Write-Host -ForegroundColor DarkCyan "Constructing cloud-init from template..."
$cloudInitTemplate = Get-Content (Join-Path $PSScriptRoot "templates" "cloud-init-compute-vm.template.yaml") -Raw
$LDAP_SECRET_PLAINTEXT = $dsvmLdapPassword
$DOMAIN_UPPER = $($config.shm.domain.fqdn).ToUpper()
$DOMAIN_LOWER = $($DOMAIN_UPPER).ToLower()
$AD_DC_NAME_UPPER = $($config.shm.dc.hostname).ToUpper()
$AD_DC_NAME_LOWER = $($AD_DC_NAME_UPPER).ToLower()
$ADMIN_USERNAME = $dsvmAdminUsername
$MACHINE_NAME = $vmName
$LDAP_USER = $config.dsg.users.ldap.dsvm.samAccountName
$LDAP_BASE_DN = $config.shm.domain.userOuPath
$LDAP_BIND_DN = "CN=" + $config.dsg.users.ldap.dsvm.name + "," + $config.shm.domain.serviceOuPath
$LDAP_FILTER = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
$cloudInitYaml = $ExecutionContext.InvokeCommand.ExpandString($cloudInitTemplate)



# Get some default VM names
# -------------------------
# Set default VM size if no argument is provided
if (!$vmSize) { $vmSize = $config.dsg.dsvm.vmSizeDefault }
# Set IP address using last IP octet
$vmIpAddress = $config.dsg.network.subnets.data.prefix + "." + $ipLastOctet
# Set machine name using last IP octet
$vmName = "DSVM-" + ($imageVersion).Replace(".", "-").ToUpper() + "-SRE-" + ($config.dsg.id).ToUpper() + "-" + $ipLastOctet



# Create the VM data disks
# ------------------------
Write-Host -ForegroundColor DarkCyan "Ensuring that VM data disks exist..."
ForEach($diskParams in (("DATA", $config.dsg.dsvm.datadisk.size_gb, $config.dsg.dsvm.datadisk.type),
                        ("HOME", $config.dsg.dsvm.homedisk.size_gb, $config.dsg.dsvm.homedisk.type))) {
    $diskId, $diskSize, $diskType = $diskParams
    $diskName = "$vmName-$diskId-DISK"
    try {
        $_ = Get-AzDisk -ResourceGroupName $config.dsg.dsvm.rg -DiskName $diskName -ErrorAction Stop
        Write-Host -ForegroundColor DarkGreen " [o] Disk '$diskName' already exists"
    } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
        Write-Host -ForegroundColor DarkCyan "Creating $diskSize GB $diskId disk ('$diskName')..."
        $diskConfig = New-AzDiskConfig -Location $config.dsg.location -DiskSizeGB $diskSize -AccountType $diskType -OsType Linux -CreateOption Empty
        $_ = New-AzDisk -ResourceGroupName $config.dsg.dsvm.rg -DiskName $diskName -Disk $diskConfig
        if ($?) {
            Write-Host -ForegroundColor DarkGreen " [o] Disk creation succeeded"
        } else {
            Write-Host -ForegroundColor DarkRed " [x] Disk creation failed!"
            throw "Disk creation failed"
        }
    }
}


# Create the VM NIC
# -----------------
Write-Host -ForegroundColor DarkCyan "Creating VM network card..."
$vmIpConfig = New-AzNetworkInterfaceIpConfig -Name "ipconfig-$vmName" -Subnet $subnet -PrivateIpAddress $vmIpAddress -Primary
$vmNic = New-AzNetworkInterface -Name "$vmName-NIC" -ResourceGroupName $config.dsg.dsvm.rg -Location $config.dsg.location -IpConfiguration $vmIpConfig -Force
if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] Network card creation succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Network card creation failed!"
    throw "Network card creation failed"
}


# Setup storage account for boot diagnostics
# ------------------------------------------
$randomSuffix = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($config.dsg.subscriptionName + $config.dsg.dsvm.rg)).ToLower() | % {$_ -replace "[^a-z]", "" }
$storageAccountName = "dsvmbootdiag" + ($config.dsg.id).ToLower() + $randomSuffix | TrimToLength 24
try {
    $_ = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $config.dsg.dsvm.rg -ErrorAction Stop
    Write-Host -ForegroundColor DarkGreen " [o] Storage account '$storageAccountName' already exists"
} catch [Microsoft.Rest.Azure.CloudException] {
    Write-Host -ForegroundColor DarkCyan " [] Creating storage account '$storageAccountName'"
    $_ = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $config.dsg.dsvm.rg -Location $config.dsg.location -SkuName "Standard_LRS" -Kind "StorageV2"
    if ($?) {
        Write-Host -ForegroundColor DarkGreen " [o] Storage account creation succeeded"
    } else {
        Write-Host -ForegroundColor DarkRed " [x] Storage account creation failed!"
        throw "Storage account creation failed"
    }
}


# Deploy the VM
# -------------
Write-Host -ForegroundColor DarkCyan "Deploying a new VM to '$vmName'..."
$adminCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $dsvmAdminUsername, (ConvertTo-SecureString -String $dsvmAdminPassword -AsPlainText -Force)
# Build VM configuration
$dsvmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
$dsvmConfig = Set-AzVMSourceImage -VM $dsvmConfig -Id $image.Id
$dsvmConfig = Set-AzVMOperatingSystem -VM $dsvmConfig -Linux -ComputerName $vmName -Credential $adminCredentials -CustomData $cloudInitYaml
$dsvmConfig = Add-AzVMNetworkInterface -VM $dsvmConfig -Id $vmNic.Id -Primary
$dsvmConfig = Add-AzVMDataDisk -VM $dsvmConfig -ManagedDiskId (Get-AzDisk -ResourceGroupName $config.dsg.dsvm.rg -DiskName "$vmName-HOME-DISK").Id -CreateOption Attach -Lun 1
$dsvmConfig = Add-AzVMDataDisk -VM $dsvmConfig -ManagedDiskId (Get-AzDisk -ResourceGroupName $config.dsg.dsvm.rg -DiskName "$vmName-DATA-DISK").Id -CreateOption Attach -Lun 2
$dsvmConfig = Set-AzVMOSDisk -VM $dsvmConfig -StorageAccountType $config.dsg.dsvm.osdisk.type -Name "$vmName-OS-DISK" -CreateOption FromImage
$dsvmConfig = Set-AzVMBootDiagnostic -VM $dsvmConfig -Enable -ResourceGroupName $config.dsg.dsvm.rg -StorageAccountName $storageAccountName


# Deploy virtual machine
# ----------------------
New-AzVM -ResourceGroupName $config.dsg.dsvm.rg -Location $config.dsg.location -VM $dsvmConfig
if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] VM creation succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] VM creation failed!"
    throw "VM creation failed"
}
Write-Host -ForegroundColor DarkCyan "VM creation finished at $(Get-Date -UFormat '%d-%b-%Y %R')"


# Poll VM to see whether it has finished running
# ----------------------------------------------
Write-Host -ForegroundColor DarkCyan "Waiting for cloud-init provisioning to finish (this will take 5+ minutes)..."
$statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.dsg.dsvm.rg -Status).Statuses.Code
$progress = 0
while (-not ($statuses.Contains("PowerState/stopped") -and $statuses.Contains("ProvisioningState/succeeded"))) {
    $statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.dsg.dsvm.rg -Status).Statuses.Code
    $progress += 1
    Write-Progress -Activity "Deployment status" -Status "$($statuses[0]) $($statuses[1])" -PercentComplete $progress
    Start-Sleep 10
}


# VM must be off for us to switch NSG, but we can restart after the switch
# ------------------------------------------------------------------------
Write-Host -ForegroundColor DarkCyan "Switching to secure NSG '$($secureNsg.Name)' at $(Get-Date -UFormat '%d-%b-%Y %R')..."
$vmNic.NetworkSecurityGroup = $secureNsg
$_ = ($vmNic | Set-AzNetworkInterface)
if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] NSG switching succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] NSG switching failed!"
    throw "NSG switching failed"
}
$_ = Start-AzVM -Name $vmName -ResourceGroupName $config.dsg.dsvm.rg


# Create Postgres roles
# ---------------------
Write-Host -ForegroundColor DarkCyan "Creating Postgres roles on $vmName..."
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
};
Write-Host -ForegroundColor DarkCyan " [ ] Ensuring Postgres DB roles and initial shared users exist on VM $vmName"
$result = Invoke-AzVMRunCommand -Name $vmName -ResourceGroupName $config.dsg.dsvm.rg `
                                -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Postgres role creation succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Postgres role creation failed!"
    throw "Postgres role creation has failed"
}


# Create local zip file
# ---------------------
$zipFilePath = Join-Path $PSScriptRoot "smoke_tests.zip"
Write-Host -ForegroundColor DarkCyan "Creating zip file of smoke tests at $zipFilePath..."
$tempDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()) "smoke_tests")
Copy-Item $PSScriptRoot/../../azure-vms/package_lists -Filter *.* -Destination (Join-Path $tempDir package_lists) -Recurse
Copy-Item $PSScriptRoot/../../azure-vms/tests -Filter *.* -Destination (Join-Path $tempDir tests) -Recurse
if (Test-path $zipFilePath) { Remove-item $zipFilePath }
Write-Host -ForegroundColor DarkCyan " [ ] Creating zip file at $zipFilePath..."
Compress-Archive -CompressionLevel NoCompression -Path $tempDir -DestinationPath $zipFilePath
if ($?) {
    Write-Host -ForegroundColor DarkGreen " [o] Zip file creation succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Zip file creation failed!"
    throw "Smoke test zip file creation has failed"
}
Remove-Item –Path $tempDir -Recurse -Force


# Upload the zip file to the compute VM
# -------------------------------------
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;
Write-Host -ForegroundColor DarkCyan "Uploading smoke tests to the compute VM..."
$zipFileEncoded = [Convert]::ToBase64String((Get-Content $zipFilePath -Raw -AsByteStream))
Remove-Item –Path $zipFilePath
# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "upload_smoke_tests.sh"
$params = @{
    PAYLOAD = $zipFileEncoded
    ADMIN_USERNAME = $dsvmAdminUsername
};
Write-Host -ForegroundColor DarkCyan " [ ] Uploading and extracting smoke tests on $vmName"
$result = Invoke-AzVMRunCommand -Name $vmName -ResourceGroupName $config.dsg.dsvm.rg `
                                -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
$success = $?
Write-Output $result.Value;
if ($success) {
    Write-Host -ForegroundColor DarkGreen " [o] Smoke test upload succeeded"
} else {
    Write-Host -ForegroundColor DarkRed " [x] Smoke test upload failed!"
    throw "Smoke test upload failed"
}


# Get private IP address for this machine
# ---------------------------------------
$privateIpAddress = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq (Get-AzVM -Name $vmName -ResourceGroupName $config.dsg.dsvm.rg).Id } | % { $_.IpConfigurations.PrivateIpAddress }
Write-Host -ForegroundColor DarkCyan "Deployment complete at $(Get-Date -UFormat '%d-%b-%Y %R')"
Write-Host -ForegroundColor DarkCyan "This new VM can be accessed with SSH or remote desktop at $privateIpAddress"
