#!/usr/bin/env bash

RESOURCE_GROUP_NAME="TIER1_RG"
LOCATION="uksouth"
VM_SIZE="Standard_DS3_v2"
DATA_DISK_SIZE_GB="1000"

ssh-keygen -m PEM -t rsa -b 4096 -f tier1_admin.pem

az group create --name $RESOURCE_GROUP_NAME --location $LOCATION

DISK=$(az disk create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name tier1_datadisk \
    --size-gb $DATA_DISK_SIZE_GB \
    --sku StandardSSD_LRS)
echo "$DISK"

DISK_NAME=$(echo "$DISK" | jq -r '.name')

VM=$(az vm create \
    --resource-group $RESOURCE_GROUP_NAME \
    --name tier1_vm \
    --image UbuntuLTS \
    --size $VM_SIZE \
    --attach-data-disks "$DISK_NAME" \
    --admin-username tier1_admin \
    --ssh-key-values ./tier1_admin.pem.pub \
    --authentication-type ssh \
    --custom-data cloud_init.yaml)
echo "$VM"

VM_IP=$(echo "$VM" | jq -r '.publicIpAddress')
sed -i'' "s/^\s*ansible_host:.*/      ansible_host: ${VM_IP}/" ./ansible/hosts.yaml
