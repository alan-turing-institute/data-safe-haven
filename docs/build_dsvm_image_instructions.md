# Safe Haven VM Image Build Instructions
These instructions will create a new VM image full analysis environment as detailed in the [analysis environment design](design/overview.md).

## Contents
1. [Prerequisites](#1-prerequisites)
2. [Provisioning a VM](#2-provision-a-vm-with-all-configured-software)
3. [Creating an image from a VM](#3-converting-candidate-vms-to-images)
4. [Registering the image in a gallery](#4-registering-images-in-the-gallery)


## 1. Prerequisites
- An Azure subscription with sufficient credits to build the environment in
- PowerShell for Azure
  - Install [PowerShell v 6.0 or above](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0)
  - Install the Azure [PowerShell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0&viewFallbackFrom=azps-1.3.0)
- SSH or OpenSSH (not tested on Windows)
- SHM configuration file
  - The core properties for the environment must be present in the `environment_configs/core` folder as described in [the Safe Haven Management deployment instructions](deploy_shm_instructions.md).

## 2. Provision a VM with all configured software
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `deployment/dsvm_images/setup` directory within the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Begin the provisioning and configuration of a new compute VM image using `./Provision_Compute_VM.ps1 -shmId <SHM ID>`, where the SHM ID is the one specified in the config
- The build (based on Ubuntu 18.04) takes approximately 6 hours of which 4 hours(!) is taken up with installing the Python 2.7 environment.

## 3. Converting candidate VMs to images
After running the build script, the build will take several hours to complete.
Information about how to monitor the build using ssh is given at the end of the `Provision_Compute_VM.ps1` script.
Once you are happy with a particular candidate, you can convert it into an image using `./Convert_VM_To_Image.ps1`.

- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `deployment/dsvm_images/setup` directory within the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Begin the provisioning and configuration of a new compute VM image using `./Convert_VM_To_Image.ps1 -shmId <SHM ID> -vmName <VM Name>`, where the SHM ID is the one specified in the config and the VM name is the name of the virtual machine created during the provisioning step
- This will build a new image in `RG_SH_IMAGE_STORAGE` and delete the VM plus associated build artifacts (hard disk, network card and public IP address)

## 4. Registering images in the gallery
Once you have created an image, it can be registered in the image gallery using the `Register_Image_In_Gallery.ps1` script.
This must be provided with the name of the image created during the conversion step and will register this in the shared gallery as a new version of the Ubuntu-based compute machine images.
This command can take between 30 minutes and 1 hour to complete, as it has to replicate the VM across 3 different regions.

- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `deployment/dsvm_images/setup` directory within the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Begin the provisioning and configuration of a new compute VM image using `./Register_Image_In_Gallery.ps1 -shmId <SHM ID> -imageName <Image Name>`, where the SHM ID is the one specified in the config and the image name is the name of the VM image created during the conversion step
- This will register the new image in the shared image gallery and replicate it across several Azure regions.
