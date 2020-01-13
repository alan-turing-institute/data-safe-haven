param(
  [Parameter(Position=0, Mandatory = $true, HelpMessage = "Enter SHM ID (usually a string e.g enter 'testa' for Turing Development Safe Haven A)")]
  [string]$shmId,
  [Parameter(Position=1, Mandatory = $true, HelpMessage = "Which tier of mirrors should be deployed")]
  [ValidateSet("2", "3")]
  [string]$tier
)

Import-Module Az
Import-Module $PSScriptRoot/../../common_powershell/Configuration.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Deployments.psm1 -Force
Import-Module $PSScriptRoot/../../common_powershell/Security.psm1 -Force

# Get config and original context before changing subscription
# ------------------------------------------------------------
$config = Get-ShmFullConfig($shmId)
$originalContext = Get-AzContext
$_ = Set-AzContext -SubscriptionId $config.subscriptionName

# Load cloud-init
$cloudInitTemplate = Get-Content (Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-mirror-external-pypi.yaml") -Raw
$tier3whitelist = Get-Content (Join-Path $PSScriptRoot ".." ".." "secure_research_enviroment" "azure-vms" "package_lists" "tier3_pypi_whitelist.list") -Raw

foreach ($package in $tier3whitelist) {
  Write-Host $package
}
# ; IF_WHITELIST_ENABLED packages =


exit 1


# # Set tier-dependent variables
# # ----------------------------
# MACHINENAME_PREFIX="${MACHINENAME_BASE}-EXTERNAL-TIER-${TIER}"
# NSG_EXTERNAL="NSG_SHM_${SHMID}_PKG_MIRRORS_EXTERNAL_TIER${TIER}"
# SUBNET_EXTERNAL="${SUBNET_PREFIX}_EXTERNAL_TIER${TIER}"
# VNETNAME="VNET_SHM_${SHMID}_PKG_MIRRORS_TIER${TIER}"
# VNET_IPTRIPLET="10.20.${TIER}"


# # Set datadisk size
# # -----------------
# if [ "$TIER" == "2" ]; then
#     PYPIDATADISKSIZE=$DATADISK_LARGE
#     PYPIDATADISKSIZEGB=$DATADISK_LARGE_NGB
#     CRANDATADISKSIZE=$DATADISK_MEDIUM
#     CRANDATADISKSIZEGB=$DATADISK_MEDIUM_NGB
# elif [ "$TIER" == "3" ]; then
#     PYPIDATADISKSIZE=$DATADISK_MEDIUM
#     PYPIDATADISKSIZEGB=$DATADISK_MEDIUM_NGB
#     CRANDATADISKSIZE=$DATADISK_SMALL
#     CRANDATADISKSIZEGB=$DATADISK_SMALL_NGB
# else
#     print_usage_and_exit
# fi


# Ensure that package mirror and networking resource groups exist
# ---------------------------------------------------------------
$_ = Deploy-ResourceGroup -Name $config.mirrors.rg -Location $config.location
$_ = Deploy-ResourceGroup -Name $config.network.vnet.rg -Location $config.location


# Set up the VNet for internal and external package mirrors
# ---------------------------------------------------------
$vnetName = "VNET_SHM_" + $($config.id).ToUpper() + "_PKG_MIRRORS_TIER$tier"
$vnetIpTriplet = "10.20.$tier"
$vnetIpRange = "$vnetIpTriplet.0/24"
$vnetPkgMirrors = Deploy-VirtualNetwork -Name $vnetName -ResourceGroupName $config.network.vnet.rg -AddressPrefix $vnetIpRange -Location $config.location


# Set up the internal and external package mirror subnets
# -------------------------------------------------------
$subnetExternalName = "ExternalPackageMirrorsTier$($tier)Subnet"
$subnetInternalName = "InternalPackageMirrorsTier$($tier)Subnet"
# External subnet
$subnetExternalIpRange = "$vnetIpTriplet.0/28"
$externalSubnet = Deploy-Subnet -Name $subnetExternalName -VirtualNetwork $vnetPkgMirrors -AddressPrefix $subnetExternalIpRange
# Internal subnet
$existingSubnetIpRanges = Get-AzVirtualNetworkSubnetConfig -VirtualNetwork $vnetPkgMirrors | % { $_.AddressPrefix }
$subnetInternalIpRange = (0..240).Where({$_ % 16 -eq 0}) | % { "$vnetIpTriplet.$_/28" } | Where { $_ -notin $existingSubnetIpRanges } | Select-Object -First 1
$_ = Deploy-Subnet -Name $subnetInternalName -VirtualNetwork $vnetPkgMirrors -AddressPrefix $subnetInternalIpRange


# Set up the NSG for external package mirrors
# -------------------------------------------
$nsgExternalName = "NSG_SHM_" + $($config.id).ToUpper() + "_PKG_MIRRORS_EXTERNAL_TIER$tier"
$externalNsg = Deploy-NetworkSecurityGroup -Name $nsgExternalName -ResourceGroupName $config.network.vnet.rg -Location $config.location
Deploy-NetworkSecurityGroupRule -NetworkSecurityGroup $externalNsg `
                                -Name "IgnoreInboundRulesBelowHere" `
                                -Description "Deny all other inbound" `
                                -Priority 3000 `
                                -Direction Inbound -Access Deny -Protocol * `
                                -SourceAddressPrefix * -SourcePortRange *  `
                                -DestinationAddressPrefix * -DestinationPortRange *
Deploy-NetworkSecurityGroupRule -NetworkSecurityGroup $externalNsg `
                                -Name "UpdateOutbound" `
                                -Description "Allow ports 443 (https) and 873 (unencrypted rsync) for updating mirrors" `
                                -Priority 300 `
                                -Direction Outbound -Access Allow -Protocol TCP `
                                -SourceAddressPrefix $subnetExternalIpRange -SourcePortRange *  `
                                -DestinationAddressPrefix Internet -DestinationPortRange 443,873
Deploy-NetworkSecurityGroupRule -NetworkSecurityGroup $externalNsg `
                                -Name "IgnoreOutboundRulesBelowHere" `
                                -Description "Deny all other outbound" `
                                -Priority 3000 `
                                -Direction Outbound -Access Deny -Protocol * `
                                -SourceAddressPrefix * -SourcePortRange *  `
                                -DestinationAddressPrefix * -DestinationPortRange *


# Set up the NSG for internal package mirrors
# -------------------------------------------
$nsgInternalName = "NSG_SHM_" + $($config.id).ToUpper() + "_PKG_MIRRORS_INTERNAL_TIER$tier"
$internalNsg = Deploy-NetworkSecurityGroup -Name $nsgInternalName -ResourceGroupName $config.network.vnet.rg -Location $config.location
Deploy-NetworkSecurityGroupRule -NetworkSecurityGroup $internalNsg `
                                -Name "RsyncInbound" `
                                -Description "Allow ports 22 and 873 for rsync" `
                                -Priority 200 `
                                -Direction Inbound -Access Allow -Protocol TCP `
                                -SourceAddressPrefix $subnetExternalIpRange -SourcePortRange *  `
                                -DestinationAddressPrefix * -DestinationPortRange 22,873
Deploy-NetworkSecurityGroupRule -NetworkSecurityGroup $internalNsg `
                                -Name "MirrorRequestsInbound" `
                                -Description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for webservices" `
                                -Priority 300 `
                                -Direction Inbound -Access Allow -Protocol TCP `
                                -SourceAddressPrefix VirtualNetwork -SourcePortRange *  `
                                -DestinationAddressPrefix * -DestinationPortRange 80,443,3128
Deploy-NetworkSecurityGroupRule -NetworkSecurityGroup $internalNsg `
                                -Name "IgnoreInboundRulesBelowHere" `
                                -Description "Deny all other inbound" `
                                -Priority 3000 `
                                -Direction Inbound -Access Deny -Protocol TCP `
                                -SourceAddressPrefix * -SourcePortRange *  `
                                -DestinationAddressPrefix * -DestinationPortRange *
Deploy-NetworkSecurityGroupRule -NetworkSecurityGroup $internalNsg `
                                -Name "IgnoreOutboundRulesBelowHere" `
                                -Description "Deny all other outbound" `
                                -Priority 3000 `
                                -Direction Outbound -Access Deny -Protocol * `
                                -SourceAddressPrefix * -SourcePortRange *  `
                                -DestinationAddressPrefix * -DestinationPortRange *


# Get common objects
# ------------------
$bootDiagnosticsAccount = Deploy-StorageAccount -Name $config.bootdiagnostics.accountName -ResourceGroupName $config.bootdiagnostics.rg -Location $config.location
$adminUsername = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName $config.keyVault.secretNames.mirrorAdminUsername -DefaultValue "mirroradmin"

# Set up PyPI external mirror
# ---------------------------
$vmName = "PYPI-MIRROR-EXTERNAL-TIER-$tier"
# Deploy NIC and data disks
$vmNic = Deploy-VirtualMachineNIC -Name "$vmName-NIC" -ResourceGroupName $config.mirrors.rg -Subnet $externalSubnet -PrivateIpAddress "$vnetIpTriplet.4" -Location $config.location
$dataDisk = Deploy-ManagedDisk -Name "$vmName-DATA-DISK" -SizeGB 8192 -Type "Standard_LRS" -ResourceGroupName $config.mirrors.rg -Location $config.location
$secondDisk = Deploy-ManagedDisk -Name "$vmName-somethingelse-DISK" -SizeGB 1024 -Type "Standard_LRS" -ResourceGroupName $config.mirrors.rg -Location $config.location


#     # Apply whitelist if this is a Tier-3 mirror
#     if [ "$TIER" == "3" ]; then
#         # Indent whitelist by twelve spaces to match surrounding text
#         TMP_WHITELIST="$(mktemp).list"
#         cp $TIER3WHITELIST $TMP_WHITELIST
#         sed -i -e 's/^/            /' $TMP_WHITELIST

#         # Build cloud-config file
#         sed -i -e "/; IF_WHITELIST_ENABLED packages =/ r ${TMP_WHITELIST}" $TMP_CLOUDINITYAML
#         sed -i -e 's/; IF_WHITELIST_ENABLED //' $TMP_CLOUDINITYAML
#         rm $TMP_WHITELIST
#     fi




# CloudInitYaml = #$ExecutionContext.InvokeCommand.ExpandString($cloudInitTemplate)
$params = @{
    Name = "PYPI-MIRROR-EXTERNAL-TIER-$tier"
    Size = "Standard_F4"
    OsDiskType = "Standard_LRS"
    AdminUsername = $adminUsername
    AdminPassword = Resolve-KeyVaultSecret -VaultName $config.keyVault.Name -SecretName ("shm-" + "$($config.shm.id)".ToLower() + "-pypi-mirror-external-tier-$tier-admin-password")
    CloudInitYaml = Get-Content (Join-Path $PSScriptRoot ".." "cloud_init" "cloud-init-mirror-external-pypi.yaml") -Raw
    NicId = $vmNic.Id
    ResourceGroupName = $config.mirrors.rg
    BootDiagnosticsAccount = $bootDiagnosticsAccount
    Location = $config.location
    DataDiskIds = @($dataDisk.Id, $secondDisk.Id)
}
Write-Host $params
Deploy-UbuntuVirtualMachine @params

exit 1


# # Set up PyPI external mirror
# # ---------------------------
# MACHINENAME="PYPI-${MACHINENAME_PREFIX}"
# if [ "$(az vm show --resource-group $RESOURCEGROUP --name $MACHINENAME 2> /dev/null)" != "" ]; then
#     echo -e "${BOLD}VM ${BLUE}$MACHINENAME${END}${BOLD} already exists in ${BLUE}$RESOURCEGROUP${END}"
# else
#     CLOUDINITYAML="${BASH_SOURCE%/*}/cloud-init-mirror-external-pypi.yaml"
#     TIER3WHITELIST="${BASH_SOURCE%/*}/package_lists/tier3_pypi_whitelist.list"
#     ADMIN_PASSWORD_SECRET_NAME="shm-pypi-mirror-external-tier-${TIER}-admin-password"

#     # Make a temporary cloud-init file that we may alter
#     TMP_CLOUDINITYAML="$(mktemp).yaml"
#     cp $CLOUDINITYAML $TMP_CLOUDINITYAML

#     # Apply whitelist if this is a Tier-3 mirror
#     if [ "$TIER" == "3" ]; then
#         # Indent whitelist by twelve spaces to match surrounding text
#         TMP_WHITELIST="$(mktemp).list"
#         cp $TIER3WHITELIST $TMP_WHITELIST
#         sed -i -e 's/^/            /' $TMP_WHITELIST

#         # Build cloud-config file
#         sed -i -e "/; IF_WHITELIST_ENABLED packages =/ r ${TMP_WHITELIST}" $TMP_CLOUDINITYAML
#         sed -i -e 's/; IF_WHITELIST_ENABLED //' $TMP_CLOUDINITYAML
#         rm $TMP_WHITELIST
#     fi

#     # Ensure that admin password is available
#     if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
#         echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME${END}"
#         az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32) --output none
#     fi
#     # Retrieve admin password from keyvault
#     ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

#     # Create the VM based off the selected source image
#     echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME${END}${BOLD} in ${BLUE}$RESOURCEGROUP${END}"
#     echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

#     # Create the data disk
#     echo -e "${BOLD}Creating ${PYPIDATADISKSIZE} datadisk...${END}"
#     DISKNAME=${MACHINENAME}-DATA-DISK
#     az disk create --resource-group $RESOURCEGROUP --name $DISKNAME --location $LOCATION --sku "Standard_LRS" --size-gb ${PYPIDATADISKSIZEGB} --output none

#     # Temporarily allow outbound internet connections through the NSG from this IP address only
#     PRIVATEIPADDRESS=${VNET_IPTRIPLET}.4
#     echo -e "${BOLD}Temporarily allowing outbound internet access on ports 80, 443 and 3128 from ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} in NSG ${BLUE}$NSG_EXTERNAL${END}${BOLD} (for installing software during deployment *only*)${END}"
#     az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name configurationOutboundTemporary --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --access "Allow" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 100 --output none
#     az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name vnetOutboundTemporary --description "Block connections to the VNet" --access "Deny" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges "*" --protocol "*" --destination-address-prefixes VirtualNetwork --priority 150 --output none

#     # Create the VM
#     echo -e "${BOLD}Creating VM...${END}"

#     OSDISKNAME=${MACHINENAME}-OS-DISK
#     az vm create \
#         --admin-password $ADMIN_PASSWORD \
#         --admin-username $ADMIN_USERNAME \
#         --attach-data-disks $DISKNAME \
#         --authentication-type password \
#         --custom-data $TMP_CLOUDINITYAML \
#         --image $SOURCEIMAGE \
#         --name $MACHINENAME \
#         --nsg "" \
#         --os-disk-name $OSDISKNAME \
#         --public-ip-address "" \
#         --private-ip-address $PRIVATEIPADDRESS \
#         --resource-group $RESOURCEGROUP \
#         --size $MIRROR_VM_SIZE \
#         --storage-sku $MIRROR_DISK_TYPE \
#         --subnet $SUBNET_EXTERNAL_ID \
#         --output none
#     echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME${END}${BOLD} server${END}"
#     rm $TMP_CLOUDINITYAML

#     # Poll VM to see whether it has finished running
#     echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
#     az vm wait --name $MACHINENAME --resource-group $RESOURCEGROUP --custom "instanceView.statuses[?code == 'PowerState/stopped'].displayStatus" --output none

#     # Delete the configuration NSG rule and restart the VM
#     echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME}${END}"
#     az network nsg rule delete --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --name configurationOutboundTemporary --output none
#     az network nsg rule delete --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --name vnetOutboundTemporary --output none
#     az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME --output none
# fi


# # Set up CRAN external mirror
# # ---------------------------
# if [ "$TIER" == "2" ]; then  # we do not support Tier-3 CRAN mirrors at present
#     MACHINENAME="CRAN-${MACHINENAME_PREFIX}"
#     if [ "$(az vm show --resource-group $RESOURCEGROUP --name $MACHINENAME 2> /dev/null)" != "" ]; then
#         echo -e "${BOLD}VM ${BLUE}$MACHINENAME${END}${BOLD} already exists in ${BLUE}$RESOURCEGROUP${END}"
#     else
#         CLOUDINITYAML="${BASH_SOURCE%/*}/cloud-init-mirror-external-cran.yaml"
#         TIER3WHITELIST="${BASH_SOURCE%/*}/package_lists/tier3_cran_whitelist.list"
#         ADMIN_PASSWORD_SECRET_NAME="shm-cran-mirror-external-tier-${TIER}-admin-password"

#         # Make a temporary cloud-init file that we may alter
#         TMP_CLOUDINITYAML="$(mktemp).yaml"
#         cp $CLOUDINITYAML $TMP_CLOUDINITYAML

#         # Apply whitelist if this is a Tier-3 mirror
#         if [ "$TIER" == "3" ]; then
#             # Build cloud-config file
#             WHITELISTED_PACKAGES=$(cat $TIER3WHITELIST | tr '\n', ' ')
#             sed -i -e "s/WHITELISTED_PACKAGES=/WHITELISTED_PACKAGES=\"${WHITELISTED_PACKAGES}\"/" $TMP_CLOUDINITYAML
#             sed -i -e 's/# IF_WHITELIST_ENABLED //' $TMP_CLOUDINITYAML
#         fi

#         # Ensure that admin password is available
#         if [ "$(az keyvault secret list --vault-name $KEYVAULT_NAME | grep $ADMIN_PASSWORD_SECRET_NAME)" = "" ]; then
#             echo -e "${BOLD}Creating admin password for ${BLUE}$MACHINENAME${END}"
#             az keyvault secret set --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --value $(head /dev/urandom | base64 | tr -dc A-Za-z0-9 | head -c 32) --output none
#         fi
#         # Retrieve admin password from keyvault
#         ADMIN_PASSWORD=$(az keyvault secret show --vault-name $KEYVAULT_NAME --name $ADMIN_PASSWORD_SECRET_NAME --query "value" | xargs)

#         # Create the VM based off the selected source image
#         echo -e "${BOLD}Creating VM ${BLUE}$MACHINENAME${END}${BOLD} in ${BLUE}$RESOURCEGROUP${END}"
#         echo -e "${BOLD}This will be based off the ${BLUE}$SOURCEIMAGE${END}${BOLD} image${END}"

#         # Create the data disk
#         echo -e "${BOLD}Creating ${CRANDATADISKSIZE} datadisk...${END}"
#         DISKNAME=${MACHINENAME}-DATA-DISK
#         az disk create --resource-group $RESOURCEGROUP --name $DISKNAME --location $LOCATION --sku "Standard_LRS" --size-gb ${CRANDATADISKSIZEGB} --output none

#         # Temporarily allow outbound internet connections through the NSG from this IP address only
#         PRIVATEIPADDRESS=${VNET_IPTRIPLET}.5
#         echo -e "${BOLD}Temporarily allowing outbound internet access on ports 80, 443 and 3128 from ${BLUE}$PRIVATEIPADDRESS${END}${BOLD} in NSG ${BLUE}$NSG_EXTERNAL${END}${BOLD} (for installing software during deployment *only*)${END}"
#         az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name configurationOutboundTemporary --description "Allow ports 80 (http), 443 (pip) and 3128 (pip) for installing software" --access "Allow" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges 80 443 3128 --protocol TCP --destination-address-prefixes Internet --priority 100 --output none
#         az network nsg rule create --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --direction Outbound --name vnetOutboundTemporary --description "Block connections to the VNet" --access "Deny" --source-address-prefixes $PRIVATEIPADDRESS --destination-port-ranges "*" --protocol "*" --destination-address-prefixes VirtualNetwork --priority 200 --output none

#         # Create the VM
#         echo -e "${BOLD}Creating VM...${END}"
#         OSDISKNAME=${MACHINENAME}-OS-DISK
#         az vm create \
#             --admin-password $ADMIN_PASSWORD \
#             --admin-username $ADMIN_USERNAME \
#             --attach-data-disks $DISKNAME \
#             --authentication-type password \
#             --custom-data $TMP_CLOUDINITYAML \
#             --image $SOURCEIMAGE \
#             --name $MACHINENAME \
#             --nsg "" \
#             --os-disk-name $OSDISKNAME \
#             --public-ip-address "" \
#             --private-ip-address $PRIVATEIPADDRESS \
#             --resource-group $RESOURCEGROUP \
#             --size $MIRROR_VM_SIZE \
#             --storage-sku $MIRROR_DISK_TYPE \
#             --subnet $SUBNET_EXTERNAL_ID \
#             --output none
#         echo -e "${BOLD}Deployed new ${BLUE}$MACHINENAME${END}${BOLD} server${END}"

#         # Poll VM to see whether it has finished running
#         echo -e "${BOLD}Waiting for VM setup to finish (this may take several minutes)...${END}"
#         az vm wait --name $MACHINENAME --resource-group $RESOURCEGROUP --custom "instanceView.statuses[?code == 'PowerState/stopped'].displayStatus" --output none

#         # Delete the configuration NSG rule and restart the VM
#         echo -e "${BOLD}Restarting VM: ${BLUE}${MACHINENAME}${END}"
#         az network nsg rule delete --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --name configurationOutboundTemporary --output none
#         az network nsg rule delete --resource-group $VNETRESOURCEGROUP --nsg-name $NSG_EXTERNAL --name vnetOutboundTemporary --output none
#         az vm start --resource-group $RESOURCEGROUP --name $MACHINENAME --output none
#     fi
# fi




# # Switch back to original subscription
# # ------------------------------------
# Set-AzContext -Context $originalContext






# # # Get SHM config
# # # --------------
# # $config = Get-ShmFullConfig($shmId)

# # # Switch to appropriate management subscription
# # $originalContext = Get-AzContext
# # $_ = Set-AzContext -SubscriptionId $config.subscriptionName;

# # # Convert arguments into the format expected by mirror deployment scripts
# # $SHM_ID = "$($config.id)".ToUpper()
# # $arguments = "-s '$($config.subscriptionName)' \
# #               -i $SHM_ID \
# #               -k $($config.keyVault.Name) \
# #               -r $($config.mirrors.rg) \
# #               -t $tier \
# #               -v $($config.network.vnet.rg)"

# # # Get path to bash scripts
# # $deployScriptDir = Join-Path (Get-Item $PSScriptRoot).Parent.Parent "new_dsg_environment" "azure-vms" -Resolve

# # # Deploy external mirror servers
# # Write-Host "Deploying external mirror servers"
# # $cmd = "$deployScriptDir/deploy_azure_external_mirror_servers.sh $arguments"
# # bash -c $cmd

# # # Deploy internal mirror servers
# # Write-Host "Deploying internal mirror servers"
# # $cmd = "$deployScriptDir/deploy_azure_internal_mirror_servers.sh $arguments"
# # bash -c $cmd

# # # Switch back to original subscription
# # $_ = Set-AzContext -Context $originalContext;
