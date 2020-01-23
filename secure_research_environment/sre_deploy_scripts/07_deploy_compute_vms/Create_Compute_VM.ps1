param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SRE ID (a short string) e.g 'sandbox' for the sandbox environment")]
  [string]$sreId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Last octet of IP address eg. '160'")]
  [string]$ipLastOctet = (Read-Host -prompt "Last octet of IP address eg. '160'"),
  [Parameter(Position=2, Mandatory = $false, HelpMessage = "Enter VM size to use (or leave empty to use default)")]
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
$deploymentNsgName = "NSG_SRE_" + $($config.sre.id).ToUpper() + "_IMAGE_DEPLOYMENT"
$secureNsgName = $config.sre.network.nsg.data.name
$vnetName = $config.sre.network.vnet.name
$subnetName = $config.sre.network.subnets.data.name




# # Register shared image gallery
# # -----------------------------
# $galleryFeatureName = "GalleryPreview"
# $galleryResourceName = "galleries/images/versions"
# Add-LogMessage -Level Info "Ensuring that this subscription has the $galleryFeatureName feature and $galleryResourceName resource enabled (this may take some time)"
# $registrationState = (Get-AzProviderFeature -FeatureName $galleryFeatureName -ProviderNamespace Microsoft.Compute).RegistrationState
# $resourceProviderState = (Register-AzResourceProvider -ProviderNamespace Microsoft.Compute).RegistrationState
# if ($registrationState -eq "NotRegistered") {
#     Write-Host -ForegroundColor DarkCyan "Registering shared image gallery feature in this subscription..."
#     Register-AzProviderFeature -FeatureName $galleryFeatureName -ProviderNamespace Microsoft.Compute
# }
# while (($registrationState -ne "Registered") -or ($resourceProviderState -ne "Registered")){
#     $registrationState = (Get-AzProviderFeature -FeatureName $galleryFeatureName -ProviderNamespace Microsoft.Compute).RegistrationState
#     $resourceProviderState = (Get-AzResourceProvider -ProviderNamespace Microsoft.Compute | Where-Object {$_.ResourceTypes.ResourceTypeName -eq "$galleryResourceName"}) | % { $_.RegistrationState}
#     Write-Host "Registration states: $registrationState and $resourceProviderState"
#     Start-Sleep 30
# }
# Add-LogMessage -Level Success "Feature registration succeeded"


# Retrieve passwords from the keyvault
# ------------------------------------
Add-LogMessage -Level Info "Creating/retrieving secrets from key vault '$($config.sre.keyVault.name)'..."
$dsvmLdapPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dsvmLdapPassword
$dsvmAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dsvmAdminPassword
$dsvmAdminUsername = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dsvmAdminUsername -DefaultValue "sre$($config.sre.id)admin".ToLower()
$dsvmDbAdminPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dsvmDbAdminPassword
$dsvmDbReaderPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dsvmDbReaderPassword
$dsvmDbWriterPassword = Resolve-KeyVaultSecret -VaultName $config.sre.keyVault.name -SecretName $config.sre.keyVault.secretNames.dsvmDbWriterPassword


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
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    $versions = Get-AzGalleryImageVersion -ResourceGroup $config.sre.dsvm.vmImageResourceGroup -GalleryName $config.sre.dsvm.vmImageGallery -GalleryImageDefinitionName $imageDefinition | Sort-Object Name | % {$_.Name} #Select-Object -Last 1
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


# Check that secure NSG exists
# ----------------------------
Add-LogMessage -Level Info "Looking for secure NSG '$secureNsgName'..."
# $secureNsg = $null
try {
    $secureNsg = Get-AzNetworkSecurityGroup -ResourceGroupName $config.sre.network.vnet.rg -Name $secureNsgName  -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    Add-LogMessage -Level Fatal "NSG '$($secureNsgName )' could not be found!"
}
Add-LogMessage -Level Success "Found secure NSG '$($secureNsg.Name)' in $($secureNsg.ResourceGroupName)"


# Check that deployment NSG exists
# --------------------------------
$deploymentNsg = Deploy-NetworkSecurityGroup -Name $deploymentNsgName -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location
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


# Add-LogMessage -Level Info "Looking for deployment NSG '$deploymentNsgName'..."
# $deploymentNsg = $null
# try {
#     $deploymentNsg = Get-AzNetworkSecurityGroup -Name $deploymentNsgName -ResourceGroupName $config.sre.network.vnet.rg -ErrorAction Stop
# } catch [Microsoft.Azure.Commands.Network.Common.NetworkCloudException] {
#     Add-LogMessage -Level Info "Creating new NSG '$($deploymentNsgName)'"
#     $shmIdentitySubnetIpRange = $config.shm.network.subnets.identity.cidr
#     # Inbound: allow LDAP then deny all
#     $ruleInbound1 = New-AzNetworkSecurityRuleConfig -Access "Allow" `
#                                                     -Description "Inbound allow LDAP" `
#                                                     -DestinationAddressPrefix "VirtualNetwork" `
#                                                     -DestinationPortRange "*" `
#                                                     -Direction "Inbound" `
#                                                     -Name "InboundAllowLDAP" `
#                                                     -Priority 2000 `
#                                                     -Protocol "*" `
#                                                     -SourceAddressPrefix $shmIdentitySubnetIpRange `
#                                                     -SourcePortRange 88,389,636
#     $ruleInbound2 = New-AzNetworkSecurityRuleConfig -Access "Deny" `
#                                                     -Description "Inbound deny all" `
#                                                     -DestinationAddressPrefix "*" `
#                                                     -DestinationPortRange "*" `
#                                                     -Direction "Inbound" `
#                                                     -Name "InboundDenyAll" `
#                                                     -Priority 3000 `
#                                                     -Protocol "*" `
#                                                     -SourceAddressPrefix "*" `
#                                                     -SourcePortRange "*"
#     # Outbound: allow LDAP then deny all Virtual Network
#     $ruleOutbound1 = New-AzNetworkSecurityRuleConfig -Access "Allow" `
#                                                      -Description "Outbound allow LDAP" `
#                                                      -DestinationAddressPrefix $shmIdentitySubnetIpRange `
#                                                      -DestinationPortRange "*" `
#                                                      -Direction "Outbound" `
#                                                      -Name "OutboundAllowLDAP" `
#                                                      -Priority 2000 `
#                                                      -Protocol "*" `
#                                                      -SourceAddressPrefix "VirtualNetwork" `
#                                                      -SourcePortRange "*"
#     $ruleOutbound2 = New-AzNetworkSecurityRuleConfig -Access "Deny" `
#                                                      -Description "Outbound deny virtual network" `
#                                                      -DestinationAddressPrefix "VirtualNetwork" `
#                                                      -DestinationPortRange "*" `
#                                                      -Direction "Outbound" `
#                                                      -Name "OutboundDenyVNet" `
#                                                      -Priority 3000 `
#                                                      -Protocol "*" `
#                                                      -SourceAddressPrefix "*" `
#                                                      -SourcePortRange "*"
#     # Create deployment NSG
#     $deploymentNsg = New-AzNetworkSecurityGroup -Name $deploymentNsgName -ResourceGroupName $config.sre.network.vnet.rg -Location $config.sre.location -SecurityRules $ruleInbound1,$ruleInbound2,$ruleOutbound1,$ruleOutbound2
# } catch {
#     Write-Host $_.Exception.GetType()
# }
# Write-Host -ForegroundColor DarkGreen " [o] Found deployment NSG '$($deploymentNsg.Name)' in $($deploymentNsg.ResourceGroupName)"


# Check that VNET and subnet exist
# --------------------------------
Add-LogMessage -Level Info "Looking for virtual network '$($config.sre.network.vnet.name)'..."
# $vnet = $null
try {
    $vnet = Get-AzVirtualNetwork -ResourceGroupName $config.sre.network.vnet.rg -Name $config.sre.network.vnet.name -ErrorAction Stop
} catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
    Add-LogMessage -Level Fatal "Virtual network '$($config.sre.network.vnet.name)' could not be found!"
}
Add-LogMessage -Level Success "Found virtual network '$($vnet.Name)' in $($vnet.ResourceGroupName)"

Add-LogMessage -Level Info "Looking for subnet network '$subnetName'..."
$subnet = $vnet.subnets | Where-Object { $_.Name -eq $subnetName }
if ($null -eq $subnet) {
    Add-LogMessage -Level Fatal "Subnet '$subnetName' could not be found in virtual network '$($vnet.Name)'!"
}
Add-LogMessage -Level Success "Found subnet '$($subnet.Name)' in $($vnet.Name)"
# Write-Host -ForegroundColor DarkGreen " [o] Found subnet '$($subnet.Name)' in $($vnet.Name)"


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
$cloudInitTemplate = Get-Content (Join-Path $PSScriptRoot "templates" "cloud-init-compute-vm.template.yaml") -Raw
$LDAP_SECRET_PLAINTEXT = $dsvmLdapPassword
$DOMAIN_UPPER = $($config.shm.domain.fqdn).ToUpper()
$DOMAIN_LOWER = $($DOMAIN_UPPER).ToLower()
$AD_DC_NAME_UPPER = $($config.shm.dc.hostname).ToUpper()
$AD_DC_NAME_LOWER = $($AD_DC_NAME_UPPER).ToLower()
$ADMIN_USERNAME = $dsvmAdminUsername
$MACHINE_NAME = $vmName
$LDAP_USER = $config.sre.users.ldap.dsvm.samAccountName
$LDAP_BASE_DN = $config.shm.domain.userOuPath
$LDAP_BIND_DN = "CN=" + $config.sre.users.ldap.dsvm.name + "," + $config.shm.domain.serviceOuPath
$LDAP_FILTER = "(&(objectClass=user)(memberOf=CN=" + $config.sre.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
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
$vmName = "DSVM-" + ($imageVersion).Replace(".", "-").ToUpper() + "-SRE-" + ($config.sre.id).ToUpper() + "-" + $ipLastOctet

# Deploy NIC and data disks
# -------------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.sre.bootdiagnostics.accountName -ResourceGroupName $config.sre.bootdiagnostics.rg -Location $config.sre.location
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Subnet $subnet -PrivateIpAddress $vmIpAddress -Location $config.sre.location
$dataDisk = Deploy-ManagedDisk -Name "$vmName-DATA-DISK" -SizeGB $config.sre.dsvm.datadisk.size_gb -Type $config.sre.dsvm.datadisk.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location
$homeDisk = Deploy-ManagedDisk -Name "$vmName-HOME-DISK" -SizeGB $config.sre.dsvm.homedisk.size_gb -Type $config.sre.dsvm.homedisk.type -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location

# Deploy the VM
# -------------
$params = @{
    Name = $vmName
    Size = $vmSize
    OsDiskType = $config.sre.dsvm.osdisk.type
    AdminUsername = $dsvmAdminUsername
    AdminPassword = $dsvmAdminPassword
    CloudInitYaml = $cloudInitYaml
    NicId = $vmNic.Id
    ResourceGroupName = $config.sre.dsvm.rg
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    Location = $config.sre.location
    DataDiskIds = @($dataDisk.Id, $homeDisk.Id)
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


# # Create the VM data disks
# # ------------------------
# Add-LogMessage -Level Info "Ensuring that VM data disks exist..."
# ForEach($diskParams in (("DATA", $config.sre.dsvm.datadisk.size_gb, $config.sre.dsvm.datadisk.type),
#                         ("HOME", $config.sre.dsvm.homedisk.size_gb, $config.sre.dsvm.homedisk.type))) {
#     $diskId, $diskSize, $diskType = $diskParams
#     $diskName = "$vmName-$diskId-DISK"
#     try {
#         $_ = Get-AzDisk -ResourceGroupName $config.sre.dsvm.rg -DiskName $diskName -ErrorAction Stop
#         Add-LogMessage -Level Success "Disk '$diskName' already exists"
#     } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
#         Write-Host -ForegroundColor DarkCyan "Creating $diskSize GB $diskId disk ('$diskName')..."
#         $diskConfig = New-AzDiskConfig -Location $config.sre.location -DiskSizeGB $diskSize -AccountType $diskType -OsType Linux -CreateOption Empty
#         $_ = New-AzDisk -ResourceGroupName $config.sre.dsvm.rg -DiskName $diskName -Disk $diskConfig
#         if ($?) {
#             Add-LogMessage -Level Success "Disk creation succeeded"
#         } else {
#             Add-LogMessage -Level Fatal "Disk creation failed!"
#         }
#     }
# }


# # Create the VM NIC
# # -----------------
# Write-Host -ForegroundColor DarkCyan "Creating VM network card..."
# $vmIpConfig = New-AzNetworkInterfaceIpConfig -Name "ipconfig-$vmName" -Subnet $subnet -PrivateIpAddress $vmIpAddress -Primary
# $vmNic = New-AzNetworkInterface -Name "$vmName-NIC" -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location -IpConfiguration $vmIpConfig -Force
# if ($?) {
#     Write-Host -ForegroundColor DarkGreen " [o] Network card creation succeeded"
# } else {
#     Write-Host -ForegroundColor DarkRed " [x] Network card creation failed!"
#     throw "Network card creation failed"
# }


# # Setup storage account for boot diagnostics
# # ------------------------------------------
# $randomSuffix = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($config.sre.subscriptionName + $config.sre.dsvm.rg)).ToLower() | % {$_ -replace "[^a-z]", "" }
# $storageAccountName = "dsvmbootdiag" + ($config.sre.id).ToLower() + $randomSuffix | TrimToLength 24
# try {
#     $_ = Get-AzStorageAccount -Name $storageAccountName -ResourceGroupName $config.sre.dsvm.rg -ErrorAction Stop
#     Write-Host -ForegroundColor DarkGreen " [o] Storage account '$storageAccountName' already exists"
# } catch [Microsoft.Rest.Azure.CloudException] {
#     Write-Host -ForegroundColor DarkCyan " [] Creating storage account '$storageAccountName'"
#     $_ = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location -SkuName "Standard_LRS" -Kind "StorageV2"
#     if ($?) {
#         Write-Host -ForegroundColor DarkGreen " [o] Storage account creation succeeded"
#     } else {
#         Write-Host -ForegroundColor DarkRed " [x] Storage account creation failed!"
#         throw "Storage account creation failed"
#     }
# }


# # Deploy the VM
# # -------------
# Write-Host -ForegroundColor DarkCyan "Deploying a new VM to '$vmName'..."
# $adminCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $dsvmAdminUsername, (ConvertTo-SecureString -String $dsvmAdminPassword -AsPlainText -Force)
# # Build VM configuration
# $dsvmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
# $dsvmConfig = Set-AzVMSourceImage -VM $dsvmConfig -Id $image.Id
# $dsvmConfig = Set-AzVMOperatingSystem -VM $dsvmConfig -Linux -ComputerName $vmName -Credential $adminCredentials -CustomData $cloudInitYaml
# $dsvmConfig = Add-AzVMNetworkInterface -VM $dsvmConfig -Id $vmNic.Id -Primary
# $dsvmConfig = Add-AzVMDataDisk -VM $dsvmConfig -ManagedDiskId (Get-AzDisk -ResourceGroupName $config.sre.dsvm.rg -DiskName "$vmName-HOME-DISK").Id -CreateOption Attach -Lun 1
# $dsvmConfig = Add-AzVMDataDisk -VM $dsvmConfig -ManagedDiskId (Get-AzDisk -ResourceGroupName $config.sre.dsvm.rg -DiskName "$vmName-DATA-DISK").Id -CreateOption Attach -Lun 2
# $dsvmConfig = Set-AzVMOSDisk -VM $dsvmConfig -StorageAccountType $config.sre.dsvm.osdisk.type -Name "$vmName-OS-DISK" -CreateOption FromImage
# $dsvmConfig = Set-AzVMBootDiagnostic -VM $dsvmConfig -Enable -ResourceGroupName $config.sre.dsvm.rg -StorageAccountName $storageAccountName


# # Deploy virtual machine
# # ----------------------
# New-AzVM -ResourceGroupName $config.sre.dsvm.rg -Location $config.sre.location -VM $dsvmConfig
# if ($?) {
#     Write-Host -ForegroundColor DarkGreen " [o] VM creation succeeded"
# } else {
#     Write-Host -ForegroundColor DarkRed " [x] VM creation failed!"
#     throw "VM creation failed"
# }
# Write-Host -ForegroundColor DarkCyan "VM creation finished at $(Get-Date -UFormat '%d-%b-%Y %R')"


# # Poll VM to see whether it has finished running
# # ----------------------------------------------
# Write-Host -ForegroundColor DarkCyan "Waiting for cloud-init provisioning to finish (this will take 5+ minutes)..."
# $statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg -Status).Statuses.Code
# $progress = 0
# while (-not ($statuses.Contains("PowerState/stopped") -and $statuses.Contains("ProvisioningState/succeeded"))) {
#     $statuses = (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg -Status).Statuses.Code
#     $progress += 1
#     Write-Progress -Activity "Deployment status" -Status "$($statuses[0]) $($statuses[1])" -PercentComplete $progress
#     Start-Sleep 10
# }


# VM must be off for us to switch NSG, but we can restart after the switch
# ------------------------------------------------------------------------
Add-LogMessage -Level Info "Switching to secure NSG '$($secureNsg.Name)' at $(Get-Date -UFormat '%d-%b-%Y %R')..."
$vmNic.NetworkSecurityGroup = $secureNsg
$_ = ($vmNic | Set-AzNetworkInterface)
if ($?) {
    Add-LogMessage -Level Success "NSG switching succeeded"
} else {
    Add-LogMessage -Level Fatal "NSG switching failed!"
}
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
# $result = Invoke-AzVMRunCommand -Name $vmName -ResourceGroupName $config.sre.dsvm.rg `
#                                 -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
# $success = $?
# Write-Output $result.Value;
# if ($success) {
#     Write-Host -ForegroundColor DarkGreen " [o] Postgres role creation succeeded"
# } else {
#     Write-Host -ForegroundColor DarkRed " [x] Postgres role creation failed!"
#     throw "Postgres role creation has failed"
# }


# Create local zip file
# ---------------------
Add-LogMessage -Level Info "Creating smoke test package for the DSVM..."
$zipFilePath = Join-Path $PSScriptRoot "smoke_tests.zip"
$tempDir = New-Item -ItemType Directory -Path (Join-Path ([System.IO.Path]::GetTempPath()) ([System.IO.Path]::GetRandomFileName()) "smoke_tests")
Copy-Item (Join-Path $PSScriptRoot ".." ".." ".." "environment_configs" "package_lists") -Filter *.* -Destination (Join-Path $tempDir package_lists) -Recurse
Copy-Item (Join-Path $PSScriptRoot ".." ".." ".." "vm_image_management" "tests") -Filter *.* -Destination (Join-Path $tempDir tests) -Recurse
if (Test-path $zipFilePath) { Remove-item $zipFilePath }
Add-LogMessage -Level Info "[ ] Creating zip file at $zipFilePath..."
Compress-Archive -CompressionLevel NoCompression -Path $tempDir -DestinationPath $zipFilePath
if ($?) {
    Add-LogMessage -Level Success "Zip file creation succeeded"
} else {
    Add-LogMessage -Level Fatal "Zip file creation failed!"
}
Remove-Item –Path $tempDir -Recurse -Force


# Upload the zip file to the compute VM
# -------------------------------------
Add-LogMessage -Level Info "Uploading smoke tests to the DSVM..."
$zipFileEncoded = [Convert]::ToBase64String((Get-Content $zipFilePath -Raw -AsByteStream))
Remove-Item –Path $zipFilePath
# Run remote script
$scriptPath = Join-Path $PSScriptRoot "remote_scripts" "upload_smoke_tests.sh"
$params = @{
    PAYLOAD = $zipFileEncoded
    ADMIN_USERNAME = $dsvmAdminUsername
};
Add-LogMessage -Level Info "[ ] Uploading and extracting smoke tests on $vmName"
$result = Invoke-RemoteScript -Shell "UnixShell" -ScriptPath $scriptPath -VMName $vmName -ResourceGroupName $config.sre.dsvm.rg -Parameter $params
Write-Output $result.Value
# $result = Invoke-AzVMRunCommand -Name $vmName -ResourceGroupName $config.sre.dsvm.rg `
#                                 -CommandId 'RunShellScript' -ScriptPath $scriptPath -Parameter $params
# $success = $?
# Write-Output $result.Value;
# if ($success) {
#     Write-Host -ForegroundColor DarkGreen " [o] Smoke test upload succeeded"
# } else {
#     Write-Host -ForegroundColor DarkRed " [x] Smoke test upload failed!"
#     throw "Smoke test upload failed"
# }


# Get private IP address for this machine
# ---------------------------------------
$privateIpAddress = Get-AzNetworkInterface | Where-Object { $_.VirtualMachine.Id -eq (Get-AzVM -Name $vmName -ResourceGroupName $config.sre.dsvm.rg).Id } | % { $_.IpConfigurations.PrivateIpAddress }
Add-LogMessage -Level Info "Deployment complete at $(Get-Date -UFormat '%d-%b-%Y %R')"
Add-LogMessage -Level Info "This new VM can be accessed with SSH or remote desktop at $privateIpAddress"
