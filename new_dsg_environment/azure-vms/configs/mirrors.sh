# Options which are configurable at the command line
KEYVAULT_NAME="kv-shm-pkg-mirrors" # must be globally unique
RESOURCEGROUP="RG_SHM_PKG_MIRRORS"
VNETRESOURCEGROUP="RG_SHM_VNET"
SHMID="" # must be provided
SUBSCRIPTION="" # must be provided
TIER="2"

# Other constants
ADMIN_USERNAME="atiadmin"
LOCATION="uksouth"
MACHINENAME_BASE="MIRROR"
SOURCEIMAGE="Canonical:UbuntuServer:18.04-LTS:latest"
SUBNET_PREFIX="SBNT_SHM_PKG_MIRRORS"

# Disk sizes
DATADISK_LARGE="8TB"
DATADISK_LARGE_NGB="8191"
DATADISK_MEDIUM="512GB"
DATADISK_MEDIUM_NGB="511"
DATADISK_SMALL="512GB"
DATADISK_SMALL_NGB="511"

# VM sizes
MIRROR_VM_SIZE="Standard_F4"
MIRROR_DISK_TYPE="Standard_LRS"
