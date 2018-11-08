# #! /bin/bash
RESOURCEGROUP=DataSafeHavenTest
MACHINENAME=DSGComputeMachineVM

TIMESTAMP="$(date '+%Y%m%d%H%M')"
BASENAME="${MACHINENAME}ForImaging-${TIMESTAMP}"
IMAGENAME="${MACHINENAME}Image-${TIMESTAMP}"
OUTPUTNAME="${MACHINENAME}-${TIMESTAMP}"

# Create resource group
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo "Creating resource group $RESOURCEGROUP"
    az group create --name $RESOURCEGROUP --location uksouth
fi

# Create the VM
echo "Creating VM $BASENAME as part of $RESOURCEGROUP"
az vm create \
  --resource-group $RESOURCEGROUP \
  --name $BASENAME \
  --image Canonical:UbuntuServer:18.04-LTS:latest \
  --custom-data cloud-init.yaml \
  --admin-username azureuser \
  --generate-ssh-keys > vm_info.json

# ssh into the new VM and read output log until installation is finished
PUBLICIP=$(grep "publicIpAddress" vm_info.json | cut -d':' -f2 | cut -d'"' -f2)
echo "Monitoring installation progress using..."
echo "ssh azureuser@${PUBLICIP}"
ssh -o "StrictHostKeyChecking no" azureuser@${PUBLICIP} <<'ENDSSH'
log_file="/var/log/cloud-init-output.log"
curr_line="$(tail -n1 $log_file)"
last_line="$(tail -n1 $log_file)"

cat $log_file
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
        curr_line="$(tail -n1 $log_file)"
        if [ "$curr_line" != "$last_line" ]
        then
                echo $curr_line
                last_line=$curr_line
        fi  
done
ENDSSH
echo "Installation finished"

# Deallocate and generalize
echo "Deallocating and generalizing VM..."
az vm deallocate --resource-group $RESOURCEGROUP --name $BASENAME
az vm generalize --resource-group $RESOURCEGROUP --name $BASENAME

# Create image and then list available images
echo "Creating an image from this VM..."
az image create --resource-group $RESOURCEGROUP --name $IMAGENAME --source $BASENAME
az image list --resource-group $RESOURCEGROUP

echo "To make a new VM from this image do:"
echo "az vm create --resource-group $RESOURCEGROUP --name $OUTPUTNAME --image $IMAGENAME --admin-username azureuser --generate-ssh-keys"

echo "To delete this image do:"
echo "az image delete --resource-group $RESOURCEGROUP --name $IMAGENAME"