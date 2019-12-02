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

# Switch to SRE subscription
$_ = Set-AzContext -Subscription $config.dsg.subscriptionName;

# Register shared image gallery
# -----------------------------
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
$dsvmAdminUsername = EnsureKeyvaultSecret -keyvaultName $config.dsg.keyVault.name -secretName $config.dsg.keyVault.secretNames.dsvmAdminUsername

$deployScriptDir = Join-Path (Get-Item $PSScriptRoot).Parent.Parent "azure-vms" -Resolve
$cloudInitDir = Join-Path $PSScriptRoot ".." ".." "dsg_configs" "cloud_init" -Resolve


# Read additional parameters that will be passed to the bash script from the config file
$adDcName = $config.shm.dc.hostname
$cloudInitYaml = "$cloudInitDir/cloud-init-compute-vm-DSG-" + $config.dsg.id + ".yaml"
$domainName = $config.shm.domain.fqdn
$ldapBaseDn = $config.shm.domain.userOuPath
$ldapBindDn = "CN=" + $config.dsg.users.ldap.dsvm.name + "," + $config.shm.domain.serviceOuPath
$ldapFilter = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
# $ldapSecretName = $config.dsg.users.ldap.dsvm.passwordSecretName
$ldapUserName = $config.dsg.users.ldap.dsvm.samAccountName
$managementKeyvault = $config.dsg.keyVault.name
$managementSubnetIpRange = $config.shm.network.subnets.identity.cidr
$sourceImage = $config.dsg.dsvm.vmImageType
$sourceImageVersion = $config.dsg.dsvm.vmImageVersion
$subscriptionSource = $config.dsg.dsvm.vmImageSubscription
$subscriptionTarget = $config.dsg.subscriptionName
$targetNsgName = $config.dsg.network.nsg.data.name
$targetRg = $config.dsg.dsvm.rg
$targetSubnet = $config.dsg.network.subnets.data.name
$targetVnet = $config.dsg.network.vnet.name

# If there is no custom cloud-init YAML file then use the default
if (-Not (Test-Path -Path $cloudInitYaml)) {
  $cloudInitYaml = Join-Path $cloudInitDir "cloud-init-compute-vm-DEFAULT.yaml" -Resolve
}
Write-Output "Using cloud-init from '$cloudInitYaml'"

# Convert arguments into the format expected by deploy_azure_dsg_vm.sh
$arguments = "-s '$subscriptionSource' \
              -t '$subscriptionTarget' \
              -i $sourceImage \
              -x $sourceImageVersion \
              -g $targetNsgName \
              -r $targetRg \
              -v $targetVnet \
              -w $targetSubnet \
              -b '$ldapBaseDn' \
              -c '$ldapBindDn' \
              -f '$ldapFilter' \
              -j $ldapUserName \
              -l $($config.dsg.keyVault.secretNames.dsvmLdapPassword) \
              -m $managementKeyvault \
              -e $managementSubnetIpRange \
              -d $domainName \
              -a $adDcName \
              -p $($config.dsg.keyVault.secretNames.dsvmAdminPassword) \
              -n $vmName \
              -y $cloudInitYaml \
              -z $vmSize"

# Add additional arguments if needed
if ($vmIpAddress) { $arguments = $arguments + " -q $vmIpAddress" }
if ($CRAN_MIRROR_URL) { $arguments = $arguments + " -o $CRAN_MIRROR_URL" }
if ($PYPI_MIRROR_URL) { $arguments = $arguments + " -k $PYPI_MIRROR_URL" }

# Write-Host $arguments
# $cmd =  "$deployScriptDir/deploy_azure_compute_vm.sh $arguments"
# bash -c $cmd

# Write-Host "Configuring Postgres shared admin, write and read users"
# $_ = Invoke-Expression -Command "$PSScriptRoot\Create_Postgres_Roles.ps1 -sreId $sreId -ipLastOctet $ipLastOctet"
# Write-Host "VM deployment done."


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
# '$($image.Id)'


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
Write-Host -ForegroundColor DarkGreen " [o] PyPI full: '$PYPI_MIRROR_URL'"
Write-Host -ForegroundColor DarkGreen " [o] PyPI host: '$PYPI_MIRROR_HOST'"


# Construct the cloud-init yaml file for the target subscription
# --------------------------------------------------------------
Write-Host -ForegroundColor DarkCyan "Constructing cloud-init from template..."
#$cloudInitPath = (New-TemporaryFile).FullName + ".yaml"
$cloudInitPath = "out.yaml"
$cloudInitTemplate = Get-Content (Join-Path $PSScriptRoot "templates" "cloud-init-compute-vm.template.yaml") -Raw
$LDAP_SECRET_PLAINTEXT = $dsvmLdapPassword
$DOMAIN_UPPER = $($config.shm.domain.fqdn).ToUpper()
$DOMAIN_LOWER = $($DOMAIN_UPPER).ToLower()
$AD_DC_NAME_UPPER = $($config.shm.dc.hostname).ToUpper()
$AD_DC_NAME_LOWER = $($AD_DC_NAME_UPPER).ToLower()
$ADMIN_USERNAME = "atiadmin"
$MACHINE_NAME = $vmName
$LDAP_USER = $config.dsg.users.ldap.dsvm.samAccountName
$LDAP_BASE_DN = $config.shm.domain.userOuPath
$LDAP_BIND_DN = "CN=" + $config.dsg.users.ldap.dsvm.name + "," + $config.shm.domain.serviceOuPath
$LDAP_FILTER = "(&(objectClass=user)(memberOf=CN=" + $config.dsg.domain.securityGroups.researchUsers.name + "," + $config.shm.domain.securityOuPath + "))"
$ExecutionContext.InvokeCommand.ExpandString($cloudInitTemplate) | Out-File $cloudInitPath
$cloudInitEncoded = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($cloudInitPath))
Get-Content $cloudInitPath -Raw



# Get some default VM names
# -------------------------
# Set default VM size if no argument is provided
if (!$vmSize) { $vmSize = $config.dsg.dsvm.vmSizeDefault }
# Set IP address if we have a fixed IP
$vmIpAddress = $null
if ($ipLastOctet) { $vmIpAddress = $config.dsg.network.subnets.data.prefix + "." + $ipLastOctet }
# Set machine name
# $vmName = "DSVM-SRE-" + (Get-Date -UFormat "%Y%m%d%H%M")
$vmName = "DSVM-SRE-" + ($imageVersion).Replace(".", "-").ToUpper()
if ($ipLastOctet) { $vmName = $vmName + "-" + $ipLastOctet }


# Create the VM disks
# -------------------
Write-Host -ForegroundColor DarkCyan "Ensuring that VM disks exist..."
ForEach($diskParams in (("DATA", $config.dsg.dsvm.datadisk.size_gb, $config.dsg.dsvm.datadisk.type),
                        ("HOME", $config.dsg.dsvm.homedisk.size_gb, $config.dsg.dsvm.homedisk.type),
                        ("OS", $config.dsg.dsvm.osdisk.size_gb, $config.dsg.dsvm.osdisk.type))) {
# ForEach($diskParams in (("DATA", $config.dsg.dsvm.datadisk.size_gb, $config.dsg.dsvm.datadisk.type),
#                         ("HOME", $config.dsg.dsvm.homedisk.size_gb, $config.dsg.dsvm.homedisk.type))) {
    $diskId, $diskSize, $diskType = $diskParams
    $diskName = "$vmName-$diskId-DISK"
    try {
        Get-AzDisk -ResourceGroupName $config.dsg.dsvm.rg -DiskName $diskName -ErrorAction Stop
        Write-Host -ForegroundColor DarkGreen " [o] Disk '$diskName' already exists"
    } catch [Microsoft.Azure.Commands.Compute.Common.ComputeCloudException] {
        Write-Host -ForegroundColor DarkCyan "Creating $diskSize GB $diskId disk ('$diskName')..."
        $diskConfig = New-AzDiskConfig -Location $config.dsg.location -DiskSizeGB $diskSize -AccountType $diskType -OsType Linux -CreateOption Empty
        New-AzDisk -ResourceGroupName $config.dsg.dsvm.rg -DiskName $diskName -Disk $diskConfig
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
Write-Host -ForegroundColor DarkCyan "Creating VM NIC..."
$vmNic = New-AzNetworkInterface -Name "$vmName-NIC" -ResourceGroupName $config.dsg.dsvm.rg -Location $config.dsg.location -SubnetId $subnet.Id -IpConfigurationName "ipconfig-$vmName" -Force #-DnsServer "8.8.8.8", "8.8.4.4"


# # Create the public IPs needed for the deployment
# $vmPip = New-AzPublicIpAddress -Name "$vmName-PIP" `
#                                -ResourceGroupName $config.dsg.dsvm.rg `
#                                -Location $config.dsg.location `
#                                -AllocationMethod Static `
#                                -IpAddressVersion IPv4 `
#                                -Sku Standard -Force





# Deploy the VM
# -------------
Write-Host -ForegroundColor DarkCyan "Deploying a new VM to '$vmName'..."
$adminCredentials = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $dsvmAdminUsername, (ConvertTo-SecureString -String $dsvmAdminPassword -AsPlainText -Force)
# $dsvm = New-AzVMConfig -VMName $vmName -VMSize $vmSize
# $dsvm = Set-AzVMOperatingSystem -VM $dsvm -Linux -ComputerName $vmName -ProvisionVMAgent -Credentials $adminCredentials #-EnableAutoUpdate
# $dsvm = Add-AzVMNetworkInterface -VM $dsvm -Id $vmNic.Id
# $dsvm = Set-AzVMOSDisk -VM $dsvm -Name $OSDiskName -VhdUri $OSDiskUri -SourceImageUri $SourceImageUri -Caching $OSDiskCaching -CreateOption "FromImage" -Linux

# Construct VM configuration
$dsvmConfig = New-AzVMConfig -VMName $vmName -VMSize $vmSize
$dsvmConfig = Set-AzVMOSDisk -VM $dsvmConfig -ManagedDiskId (Get-AzDisk -ResourceGroupName $config.dsg.dsvm.rg -DiskName "$vmName-OS-DISK").Id -CreateOption Empty
$dsvmConfig = Add-AzVMDataDisk -VM $dsvmConfig -ManagedDiskId (Get-AzDisk -ResourceGroupName $config.dsg.dsvm.rg -DiskName "$vmName-HOME-DISK").Id -CreateOption Empty -Lun 1
# $dsvmConfig = Add-AzVMDataDisk -VM $dsvmConfig -Name "$vmName-HOME-DISK" -DiskSizeInGB $config.dsg.dsvm.homedisk.size_gb -Lun 0 -CreateOption Empty
$dsvmConfig = Add-AzVMDataDisk -VM $dsvmConfig -ManagedDiskId (Get-AzDisk -ResourceGroupName $config.dsg.dsvm.rg -DiskName "$vmName-DATA-DISK").Id -CreateOption Empty -Lun 2
# $dsvmConfig = Add-AzVMDataDisk -VM $dsvmConfig -ManagedDiskId (Get-AzDisk -ResourceGroupName $config.dsg.dsvm.rg -DiskName "$vmName-DATA-DISK").Id -Lun 2
$dsvmConfig = Add-AzVMNetworkInterface -VM $dsvmConfig -Id $vmNic.Id -Primary
$dsvmConfig = Set-AzVMOperatingSystem -VM $dsvmConfig -Linux -ComputerName $vmName -Credential $adminCredentials -CustomData $cloudInitEncoded
$dsvmConfig = Set-AzVMSourceImage -VM $dsvmConfig -Id $image.Id

# Virtual Machine
New-AzVM -ResourceGroupName $config.dsg.dsvm.rg -Location $config.dsg.location -VM $dsvmConfig



# Write-Host $image.Id
# New-AzVM -Name $vmName `
#          -ResourceGroupName $config.dsg.dsvm.rg `
#          -ImageName $image.Id `
#          -Location $config.dsg.location `
#          -SubnetName $subnet.Id `
#          -SecurityGroupName $deploymentNsg.Id `
#          -Credential $adminCredentials `
#          -PublicIpAddressName ""



# New-AzVM

# # Construct the cloud-init yaml file for the target subscription
# # --------------------------------------------------------------
# # Retrieve admin password from keyvault
# ADMIN_PASSWORD=$(az keyvault secret show --vault-name $MANAGEMENT_VAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)



# DEPLOYMENT_NSG_ID=$(az network nsg show --resource-group $DSG_NSG_RG --name $DEPLOYMENT_NSG --query 'id' | xargs)
# echo -e "${BOLD}Deploying into NSG ${BLUE}$DEPLOYMENT_NSG${END} ${BOLD}with outbound internet access to allow package installation. Will switch NSGs at end of deployment.${END}"

# # Create the VM based off the selected source image
# # -------------------------------------------------
# echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME${END} ${BOLD}as part of ${BLUE}$RESOURCEGROUP${END}"
# echo -e "${BOLD}This will use the ${BLUE}$SOURCEIMAGE${END}${BOLD}-based compute machine image${END}"
# echo -e "${BOLD}Starting deployment at $(date)${END}"
# STARTTIME=$(date +%s)

# # If using the Data Science VM then the terms must be added before creating the VM
# PLANDETAILS=""
# if [[ "$SOURCEIMAGE" == *"DataScienceBase"* ]]; then
#     PLANDETAILS="--plan-name linuxdsvmubuntubyol --plan-publisher microsoft-ads --plan-product linux-data-science-vm-ubuntu"
# fi



# if [ "$IP_ADDRESS" = "" ]; then
#     echo -e "${BOLD}Requesting a dynamic IP address${END}"
#     az vm create ${PLANDETAILS} \
#         --admin-password $ADMIN_PASSWORD \
#         --admin-username $USERNAME \
#         --attach-data-disks $DATA_DISK_NAME \
#         --custom-data $TMP_CLOUD_CONFIG_YAML \
#         --image $IMAGE_ID \
#         --name $MACHINENAME \
#         --nsg $DEPLOYMENT_NSG_ID \
#         --os-disk-name "${MACHINENAME}OSDISK" \
#         --os-disk-size-gb $OS_DISK_SIZE_GB \
#         --public-ip-address "" \
#         --resource-group $RESOURCEGROUP \
#         --size $VM_SIZE \
#         --storage-sku $OS_DISK_TYPE \
#         --subnet $DSG_SUBNET_ID \
#         --output none
# else
#     echo -e "${BOLD}Creating VM with static IP address ${BLUE}$IP_ADDRESS${END}"
#     az vm create ${PLANDETAILS} \
#         --admin-password $ADMIN_PASSWORD \
#         --admin-username $USERNAME \
#         --attach-data-disks $DATA_DISK_NAME \
#         --custom-data $TMP_CLOUD_CONFIG_YAML \
#         --image $IMAGE_ID \
#         --name $MACHINENAME \
#         --nsg $DEPLOYMENT_NSG_ID \
#         --os-disk-name "${MACHINENAME}OSDISK" \
#         --os-disk-size-gb $OS_DISK_SIZE_GB \
#         --private-ip-address $IP_ADDRESS \
#         --public-ip-address "" \
#         --resource-group $RESOURCEGROUP \
#         --size $VM_SIZE \
#         --storage-sku $OS_DISK_TYPE \
#         --subnet $DSG_SUBNET_ID \
#         --output none
# fi
# # Remove temporary init file if it exists
# rm $TMP_CLOUD_CONFIG_YAML 2> /dev/null
# echo -e "${BOLD}VM creation finished at $(date)${END}"
# echo -e "${BOLD}Running cloud-init for deployment...${END}"

# # allow some time for the system to finish initialising
# sleep 30

# # Poll VM to see whether it has finished running
# echo -e "${BOLD}Waiting for VM setup to finish (this will take 5+ minutes)...${END}"
# # Check that VM is down by requiring "PowerState/stopped" and "ProvisioningState/succeeded"
# az vm wait --name $MACHINENAME --resource-group $RESOURCEGROUP --custom "length((instanceView.statuses[].code)[?(contains(@, 'PowerState/stopped') || contains(@, 'ProvisioningState/succeeded'))]) == \`2\`"

# # VM must be off for us to switch NSG. Once done we restart
# echo -e "${BOLD}Switching to secure NSG ${BLUE}${DSG_NSG}${END} ${BOLD}at $(date)${END}"
# az network nic update --resource-group $RESOURCEGROUP --name "${MACHINENAME}VMNic" --network-security-group $DSG_NSG_ID --output none
# echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME}${END} ${BOLD}at $(date)${END}"
# az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME

# # Poll VM to see whether it has finished restarting
# echo -e "${BOLD}Waiting for VM to restart...${END}"
# # Check that VM is up by requiring "PowerState/running" and "ProvisioningState/succeeded"
# az vm wait --name $MACHINENAME --resource-group $RESOURCEGROUP --custom "length((instanceView.statuses[].code)[?(contains(@, 'PowerState/running') || contains(@, 'ProvisioningState/succeeded'))]) == \`2\`"

# # Get public IP address for this machine. Piping to echo removes the quotemarks around the address
# PRIVATEIP=$(az vm list-ip-addresses --resource-group $RESOURCEGROUP --name $MACHINENAME --query "[0].virtualMachine.network.privateIpAddresses[0]" -o tsv)
# echo -e "${BOLD}Deployment complete at $(date)${END}"
# echo -e "${BOLD}This new VM can be accessed with SSH or remote desktop at ${BLUE}${PRIVATEIP}${END}"
