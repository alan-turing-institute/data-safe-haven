# #! /bin/bash
RESOURCEGROUP=DataSafeHavenTest
MACHINENAME=DSGComputeMachineVM

TIMESTAMP="$(date '+%Y%m%d%H%M')"
BASENAME="${MACHINENAME}ForImaging-${TIMESTAMP}"
IMAGENAME="${MACHINENAME}Image-${TIMESTAMP}"
OUTPUTNAME="${MACHINENAME}-${TIMESTAMP}"

RED="\033[0;31m"
BLUE="\033[0;34m"
END="\033[0m"

# Create resource group
if [ $(az group exists --name $RESOURCEGROUP) != "true" ]; then
    echo "Creating resource group $RESOURCEGROUP"
    az group create --name $RESOURCEGROUP --location uksouth
fi

# Create the VM
echo -e " ${RED}Creating VM ${BLUE}$BASENAME ${RED}as part of ${BLUE}$RESOURCEGROUP${END}"
az vm create \
  --resource-group $RESOURCEGROUP \
  --name $BASENAME \
  --image Canonical:UbuntuServer:18.04-LTS:latest \
  --data-disk-sizes-gb 40 \
  --custom-data cloud-init.yaml \
  --admin-username azureuser \
  --generate-ssh-keys > $BASENAME.json

# ssh into the new VM and read output log until installation is finished
PUBLICIP=$(grep "publicIpAddress" $BASENAME.json | cut -d':' -f2 | cut -d'"' -f2)
rm $BASENAME.json
echo -e "${RED}Monitoring installation progress using... ${BLUE}ssh azureuser@${PUBLICIP}${END}"
ssh -o "StrictHostKeyChecking no" azureuser@${PUBLICIP} <<'ENDSSH'
log_file="/var/log/cloud-init-output.log"

tail -f -n +1 $log_file &
TAILPID=$(jobs -p)
while [ ! -f /var/lib/cloud/instance/boot-finished ]; do
    sleep 1
done
kill $TAILPID

cloud-init status
ENDSSH
echo -e "${RED}Installation finished${END}"
echo "ssh azureuser@${PUBLICIP}"

# Deallocate and generalize
echo -e "${RED}Deallocating and generalizing VM...${END}"
az vm deallocate --resource-group $RESOURCEGROUP --name $BASENAME
az vm generalize --resource-group $RESOURCEGROUP --name $BASENAME

# Create image and then list available images
echo -e "${RED}Creating an image from this VM...${END}"
az image create --resource-group $RESOURCEGROUP --name $IMAGENAME --source $BASENAME
az image list --resource-group $RESOURCEGROUP

echo -e "${RED}To make a new VM from this image do:${END}"
echo -e "${BLUE}az vm create --resource-group $RESOURCEGROUP --name $OUTPUTNAME --image $IMAGENAME --admin-username azureuser --generate-ssh-keys${END}"
echo -e "To use this new VM with remote desktop..."
echo -e "... port 3389 needs to be opened: ${BLUE}az vm open-port --resource-group $RESOURCEGROUP --name $OUTPUTNAME --port 3389${END}"
echo -e "... a user account with a password is needed: ${BLUE}sudo passwd <USERNAME>${END}"
echo -e "... a default desktop is needed - eg. for xfce: ${BLUE}echo xfce4-session >~/.xsession${END}"
echo -e "See https://docs.microsoft.com/en-us/azure/virtual-machines/linux/use-remote-desktop for more details"

echo -e "${RED}To delete this image do:${END}"
echo -e "${BLUE}az image delete --resource-group $RESOURCEGROUP --name $IMAGENAME${END}"
