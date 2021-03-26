# Safe Haven VM Image Build Instructions

These instructions will walk you through creating a new VM image for use in the secure research environment.

## Contents

+ [:seedling: 1. Prerequisites](#seedling-1-prerequisites)
+ [:gift: 2. (Optional) Customising the build image](#new-2-customising-the-build-image)
+ [:gift: 3. Provisioning a VM](#gift-3-provision-a-vm-with-all-configured-software)
+ [:camera: 4. Converting candidate VMs to images](#camera-4-converting-candidate-vms-to-images)
+ [:art: 5. Registering images in the gallery](#art-5-registering-images-in-the-gallery)

## Explanation of symbols used in this guide

![Powershell](https://img.shields.io/badge/local-estimate%20of%20time%20needed-blue?logo=powershell&style=for-the-badge)

+ This indicates a `Powershell` command which you will need to run locally on your machine
+ Ensure you have checked out the appropriate version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
+ Open a `Powershell` terminal and navigate to the indicated directory of your locally checked-out version of the Safe Haven repository
+ Ensure that you are logged into Azure by running the `Connect-AzAccount` command
  + :pencil: If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
+ This command will give you a URL and a short alphanumeric code.
  + You will need to visit that URL in a web browser, enter the code and log in to your account on Azure
  + :pencil: If you have several Azure accounts, make sure you use one that has permissions to make changes to the subscription you are using

![Remote](https://img.shields.io/badge/remote-estimate%20of%20time%20needed-blue?logo=microsoft-onedrive&style=for-the-badge)

+ This indicates a command which you will need to run remotely on an Azure virtual machine (VM) using `Microsoft Remote Desktop`
+ Open `Microsoft Remote Desktop` and click `Add Desktop` / `Add PC`
+ Enter the private IP address of the VM that you need to connect to in the `PC name` field (this can be found by looking in the Azure portal)
+ Enter the name of the VM (for example `DC1-SHM-TESTA`) in the `Friendly name` field
+ Click `Add`
+ Ensure you are connected to the SHM VPN that you have set up
+ Double click on the desktop that appears under `Saved Desktops` or `PCs`.
+ Use the `username` and `password` specified by the appropriate section of the guide
+ :pencil: If you see a warning dialog that the certificate cannot be verified as root, accept this and continue.

![Azure Portal](https://img.shields.io/badge/portal-estimate%20of%20time%20needed-blue?logo=microsoft-azure&style=for-the-badge)

+ This indicates an operation which needs to be carried out in the [`Azure Portal`](https://portal.azure.com) using a web browser on your local machine.
+ You will need to login to the portal using an account with privileges to make the necessary changes to the resources you are altering

:pencil: **Notes**

+ This indicates some explanatory notes or examples that provide additional context for the current step.

:warning: **Troubleshooting**

+ This indicates a set of troubleshooting instructions to help diagnose and fix common problems with the current step.

![macOS](https://img.shields.io/badge/-555?&logo=apple&logoColor=white)![Windows](https://img.shields.io/badge/-555?&logo=windows&logoColor=white)![Linux](https://img.shields.io/badge/-555?&logo=linux&logoColor=white)

+ These indicate steps that depend on the OS that you are using to deploy the SRE

## :seedling: 1. Prerequisites

+ An Azure subscription with sufficient credits to build the environment in
+ PowerShell for Azure
  + Install [PowerShell v6.0 or above](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0)
  + Install the Azure [PowerShell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0&viewFallbackFrom=azps-1.3.0)
+ SSH or OpenSSH (not tested on Windows)
+ SHM configuration file
  + The core properties for the environment must be present in the `environment_configs/core` folder as described in [the Safe Haven Management deployment instructions](how-to-deploy-shm.md).


## :gift: 2. (Optional) Customising the build image

Provisioning a VM with all the Safe Haven software is done using [cloud-init](https://cloudinit.readthedocs.io/en/latest/). This takes a basic Ubuntu image and installs and configures all the necessary software packages. The cloud-init file used here is in the `deployment/dsvm_images/cloud-init` folder. The most common changes to this image that you are likely to want to make are to add a new package or to update the version of an existing package.

#### Adding a new apt package

+ Add the name of the package to `deployment/dsvm_images/packages/packages-apt.list`
+ If this package adds a new executable that you would like to be available to the end user, you should also add a check for this to the end of `deployment/dsvm_images/cloud_init/cloud-init-buildimage-ubuntu.yaml`
  + For example, to check for `Azure Data Studio` , the following line was added:
  ```bash
  if [ "$(which azuredatastudio)" ]; then echo "\n\n*azuredatastudio*\n\n$(which azuredatastudio)"; else echo "ERROR azuredatastudio not found!"; exit 1; fi
  ```

#### Adding a new Python package

+ Add the name of the package as it appears on `PyPI` to each of the package lists (supported Python versions only):
  + `deployment/dsvm_images/packages/packages-python-pypi-36.list`
  + `deployment/dsvm_images/packages/packages-python-pypi-37.list`
  + `deployment/dsvm_images/packages/packages-python-pypi-38.list`
+ If there are any restrictions on acceptable versions for this package (e.g. a minimum or exact version) then add an entry to the appropriate section in `deployment/dsvm_images/packages/python-requirements.json`
+ You should also add this package to the **whitelist** used by Tier-3 package mirrors in `environment_configs/package_lists/whitelist-core-python-pypi-tier3.list`

#### Adding a new R package

+ Add the name of the package as it appears on `CRAN` or `Bioconductor` to the appropriate package list:
  + `deployment/dsvm_images/packages/packages-r-bioconductor.list`
  + `deployment/dsvm_images/packages/packages-r-cran.list`
+ If this `R` package is available as a pre-compiled apt binary (eg. `abind` is available as `r-cran-abind` ) then add it to `deployment/dsvm_images/packages/packages-apt.list` if so
+ You should also add this package to the **whitelist** used by Tier-3 package mirrors in `environment_configs/package_lists/whitelist-core-r-cran-tier3.list`

#### Adding packages to the package whitelist

+ When you add a new package to either the `PyPI` or `CRAN` whitelist you should also determine all of its dependencies (and their dependencies, recursively)
+ Once you have the list of packages you should add them to:
  + **PyPI:** `environment_configs/package_lists/whitelist-full-python-pypi-tier3.list`
  + **CRAN:** `environment_configs/package_lists/whitelist-full-r-cran-tier3.list`

#### Changing the version of a package

If you want to update the version of one of the packages we install from a `.deb` file (eg. `dbeaver` ), you will need to edit `deployment/dsvm_images/cloud-init`

+ Find the appropriate `/installation/<package name>.debinfo` section under the `write_files:` key
+ Update the version number and the `sha256` hash for the file
+ Check that the file naming structure still matches the format described in this `.debinfo` file

## :gift: 3. Provision a VM with all configured software

In order to provision a candidate VM you will need to do the following:

![Powershell](https://img.shields.io/badge/local-two%20to%20three%20hours-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/dsvm_images/setup`

```pwsh
./Provision_Compute_VM.ps1 -shmId <SHM ID>
```

+ where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE

Once you have launched a new build by running the `./Provision_Compute_VM.ps1` script, the build will take several hours to complete (currently this is approximately **2h30**).
During this time, you can monitor the build by accessing the machine using `ssh` and either reading through the full build log at `/var/log/cloud-init-output.log` or running the summary script using `/opt/verification/analyse_build.py` .
Note that the VM will automatically shutdown at the end of the cloud-init process - if you want to analyse the build after this point, you will need to turn it back on in the Azure portal.

## :camera: 4. Converting candidate VMs to images

Once you are happy with a particular candidate, you can convert it into an image as follows:

![Powershell](https://img.shields.io/badge/local-ten%20minutes-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/dsvm_images/setup`

```pwsh
./Convert_VM_To_Image.ps1 -shmId <SHM ID> -vmName <VM name>
```

+ where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
+ where `<VM name>` is the name of the virtual machine created during the provisioning step

This will build a new image in `RG_SH_IMAGE_STORAGE` and delete the VM plus associated build artifacts (hard disk, network card and public IP address)

## :art: 5. Registering images in the gallery

Once you have created an image, it can be registered in the image gallery using the `Register_Image_In_Gallery.ps1` script.

![Powershell](https://img.shields.io/badge/local-one%20hour-blue?logo=powershell&style=for-the-badge) at :file_folder: `./deployment/dsvm_images/setup`

```pwsh
./Register_Image_In_Gallery.ps1 -shmId <SHM ID> -vmName -imageName <Image name>
```

+ where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
+ where `<Image Name>` is the name of the VM image created during the conversion step

This will register the image in the shared gallery as a new version of the Ubuntu-based compute machine images.
This command can take between 30 minutes and 1 hour to complete, as it has to replicate the VM across 3 different regions.