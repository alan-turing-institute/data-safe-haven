# Safe Haven VM Image Build Instructions

These instructions will walk you through creating a new VM image for use in the secure research environment.

## Contents

+ [:seedling: 1. Prerequisites](#seedling-1-prerequisites)
+ [:gift: 2. (Optional) Customise the build configuration](#gift-2-optional-customise-the-build-configuration)
+ [:construction_worker: 3. Build a release candidate](#construction_worker-3-build-a-release-candidate)
+ [:camera: 4. Convert candidate VM to an image](#camera-4-convert-candidate-vm-to-an-image)
+ [:art: 5. Register image in the gallery](#art-5-register-image-in-the-gallery)

## Explanation of symbols used in this guide

![Powershell: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=estimate%20of%20time%20needed)

+ This indicates a `Powershell` command which you will need to run locally on your machine
+ Ensure you have checked out the appropriate version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
+ Open a `Powershell` terminal and navigate to the indicated directory of your locally checked-out version of the Safe Haven repository
+ Ensure that you are logged into Azure by running the `Connect-AzAccount` command
  + :pencil: If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into.
+ This command will give you a URL and a short alphanumeric code.
  + You will need to visit that URL in a web browser, enter the code and log in to your account on Azure
  + :pencil: If you have several Azure accounts, make sure you use one that has permissions to make changes to the subscription you are using

![Remote: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-onedrive&label=remote&color=blue&message=estimate%20of%20time%20needed)

+ This indicates a command which you will need to run remotely on an Azure virtual machine (VM) using `Microsoft Remote Desktop`
+ Open `Microsoft Remote Desktop` and click `Add Desktop` / `Add PC`
+ Enter the private IP address of the VM that you need to connect to in the `PC name` field (this can be found by looking in the Azure portal)
+ Enter the name of the VM (for example `DC1-SHM-TESTA`) in the `Friendly name` field
+ Click `Add`
+ Ensure you are connected to the SHM VPN that you have set up
+ Double click on the desktop that appears under `Saved Desktops` or `PCs`.
+ Use the `username` and `password` specified by the appropriate section of the guide
+ :pencil: If you see a warning dialog that the certificate cannot be verified as root, accept this and continue.

![Portal: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-azure&label=portal&color=blue&message=estimate%20of%20time%20needed)

+ This indicates an operation which needs to be carried out in the [`Azure Portal`](https://portal.azure.com) using a web browser on your local machine.
+ You will need to login to the portal using an account with privileges to make the necessary changes to the resources you are altering

![Azure AD: estimate of time needed](https://img.shields.io/static/v1?style=for-the-badge&logo=microsoft-academic&label=Azure%20AD&color=blue&message=estimate%20of%20time%20needed)

+ This indicates an operation which needs to be carried out in the [`Azure Portal`](https://portal.azure.com) using a web browser on your local machine.
+ You will need to login to the portal using an account with administrative privileges on the `Azure Active Directory` that you are altering.
+ Note that this might be different from the account which is able to create/alter resources in the Azure subscription where you are building the Safe Haven.

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

### (Optional) Verify code version

If you have cloned/forked the code from our GitHub repository, you can confirm which version of the data safe haven you are currently using by running the following commands:

![Powershell: a few seconds](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20seconds)

```powershell
PS> git fetch; git pull; git status; git log -1 --pretty="At commit %h (%H)"
```

This will verify that you are on the correct branch and up to date with `origin`. You can include this confirmation in any record you keep of your deployment.

## :gift: 2. (Optional) Customise the build configuration

Provisioning a VM with all the Safe Haven software is done using [cloud-init](https://cloudinit.readthedocs.io/en/latest/). This takes a basic Ubuntu image and installs and configures all the necessary software packages.

In general, this image should cover most use cases, but it's possible that you may want to customise it for your particular circumstances, for example if you want to add a new package or to update the version of an existing package.

### Adding a new apt package

+ Add the name of the package to `deployment/dsvm_images/packages/packages-apt.list`
+ If this package adds a new executable that you would like to be available to the end user, you should also add a check for this to the end of `deployment/dsvm_images/cloud_init/cloud-init-buildimage-ubuntu.yaml`
  + For example, to check for `Azure Data Studio` , the following line was added:

  ```bash
  if [ "$(which azuredatastudio)" ]; then echo "\n\n*azuredatastudio*\n\n$(which azuredatastudio)"; else echo "ERROR azuredatastudio not found!"; exit 1; fi
  ```

### Adding a new Python package

+ Add the name of the package as it appears on `PyPI` to each of the package lists (supported Python versions only):
  + `deployment/dsvm_images/packages/packages-python-pypi-36.list`
  + `deployment/dsvm_images/packages/packages-python-pypi-37.list`
  + `deployment/dsvm_images/packages/packages-python-pypi-38.list`
+ If there are any restrictions on acceptable versions for this package (e.g. a minimum or exact version) then add an entry to the appropriate section in `deployment/dsvm_images/packages/python-requirements.json`
+ You should also add this package to the **allowlist** used by Tier-3 package mirrors in `environment_configs/package_lists/allowlist-core-python-pypi-tier3.list`

### Adding a new R package

+ Add the name of the package as it appears on `CRAN` or `Bioconductor` to the appropriate package list:
  + `deployment/dsvm_images/packages/packages-r-bioconductor.list`
  + `deployment/dsvm_images/packages/packages-r-cran.list`
+ If this `R` package is available as a pre-compiled apt binary (eg. `abind` is available as `r-cran-abind` ) then add it to `deployment/dsvm_images/packages/packages-apt.list` if so
+ You should also add this package to the **allowlist** used by Tier-3 package mirrors in `environment_configs/package_lists/allowlist-core-r-cran-tier3.list`

#### Adding packages to the package allowlist

+ When you add a new package to either the `PyPI` or `CRAN` allowlist you should also determine all of its dependencies (and their dependencies, recursively)
+ Once you have the list of packages you should add them to:
  + **PyPI:** `environment_configs/package_lists/allowlist-full-python-pypi-tier3.list`
  + **CRAN:** `environment_configs/package_lists/allowlist-full-r-cran-tier3.list`

### Changing the version of a package

If you want to update the version of one of the packages we install from a `.deb` file (eg. `RStudio`), you will need to edit `deployment/dsvm_images/cloud_init/cloud-init-buildimage-ubuntu.yaml`

+ Find the appropriate `/installation/<package name>.debinfo` section under the `write_files:` key
+ Update the version number and the `sha256` hash for the file
+ Check that the file naming structure still matches the format described in this `.debinfo` file

## :construction_worker: 3. Build a release candidate

In order to provision a candidate VM you will need to do the following:

![Powershell: two to three hours](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=two%20to%20three%20hours) at :file_folder: ``./deployment/dsvm_images/setup`

```powershell
PS> ./Provision_Compute_VM.ps1 -shmId <SHM ID>
```

+ where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE

### :pencil: Notes

+ Although the `./Provision_Compute_VM.ps1` script will finish running in a few minutes, the build itself will take several hours.
+ We recommend **monitoring** the build by accessing the machine using `ssh` and either reading through the full build log at `/var/log/cloud-init-output.log` or running the summary script using `/opt/verification/analyse_build.py`.
+ Note that the VM will automatically shutdown at the end of the cloud-init process - if you want to analyse the build after this point, you will need to turn it back on in the Azure portal.

### :warning: Troubleshooting

+ If you are unable to access the VM over `ssh` please check whether you are trying to connect from one of the approved IP addresses that you defined under `vmImages > buildIpAddresses` in the SHM config file.
+ You can check which IP addresses are currently allowed by looking at the `AllowBuildAdminSSH` inbound connection rule in the `RG_SH_NETWORKING > NSG_IMAGE_BUILD` network security group in the subscription where you are building the candidate VM

## :camera: 4. Convert candidate VM to an image

Once you are happy with a particular candidate, you can convert it into an image as follows:

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at :file_folder: ``./deployment/dsvm_images/setup`

```powershell
PS> ./Convert_VM_To_Image.ps1 -shmId <SHM ID> -vmName <VM name>
```

+ where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
+ where `<VM name>` is the name of the virtual machine created during the provisioning step

This will build a new image in `RG_SH_IMAGE_STORAGE` and delete the VM plus associated build artifacts (hard disk, network card and public IP address)

### :pencil: Notes

The first step of this script will run the remote build analysis script. Please **check** that everything has built correctly before proceeding.

## :art: 5. Register image in the gallery

Once you have created an image, it can be registered in the image gallery for future use using the `Register_Image_In_Gallery.ps1` script.

![Powershell: one hour](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=one%20hour) at :file_folder: ``./deployment/dsvm_images/setup`

```powershell
PS> ./Register_Image_In_Gallery.ps1 -shmId <SHM ID> -vmName -imageName <Image name>
```

+ where `<SHM ID>` is the [management environment ID](how-to-deploy-shm.md#management-environment-id) for this SRE
+ where `<Image Name>` is the name of the VM image created during the conversion step

This will register the image in the shared gallery as a new version of the Ubuntu-based compute machine images.
This command can take between 30 minutes and 1 hour to complete, as it has to replicate the VM across 3 different regions.
