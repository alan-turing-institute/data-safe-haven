# Safe Haven VM Image Build Instructions
These instructions will create a new VM image full analysis environment as detailed in the [analysis environment design](design/overview.md).

## Contents
- [:seedling: Prerequisites](#seedling-prerequisites)
- [:gift: Provisioning a VM](#gift-provision-a-vm-with-all-configured-software)
  - [:new: Updating the build image definition](#new-updating-the-build-image-definition)
  - [:running: Running the image build](#running-running-the-image-build)
- [:camera: Converting candidate VMs to images](#camera-converting-candidate-vms-to-images)
- [:art: Registering images in the gallery](#art-registering-images-in-the-gallery)


## :seedling: Prerequisites
- An Azure subscription with sufficient credits to build the environment in
- PowerShell for Azure
  - Install [PowerShell v6.0 or above](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0)
  - Install the Azure [PowerShell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0&viewFallbackFrom=azps-1.3.0)
- SSH or OpenSSH (not tested on Windows)
- SHM configuration file
  - The core properties for the environment must be present in the `environment_configs/core` folder as described in [the Safe Haven Management deployment instructions](deploy_shm_instructions.md).


## :gift: Provision a VM with all configured software
Provisioning a VM with all the Safe Haven software is done using [cloud-init](https://cloudinit.readthedocs.io/en/latest/).
This takes a basic Ubuntu image and installs and configures all the necessary software packages.
The cloud-init file used here is in the `deployment/dsvm_images/cloud-init` folder.

### :new: Updating the build image definition
The most common changes to this image that you are likely to want to make are to add new package or to update the version of existing packages.

**Adding a new apt package**
- Add the name of the package to `deployment/dsvm_images/packages/packages-apt.list`
- If this package adds a new executable that you would like to be available to the end user, you should also add a check for this to the end of `deployment/dsvm_images/cloud_init/cloud-init-buildimage-ubuntu.yaml`

> For example, to check for `Azure Data Studio`, the following line was added:
>
> `if [ "$(which azuredatastudio)" ]; then echo "\n\n*azuredatastudio*\n\n$(which azuredatastudio)"; else echo "ERROR azuredatastudio not found!"; exit 1; fi`

**Adding a new Python package**
- Add the name of the package as it appears on `PyPI` to each of
  - `deployment/dsvm_images/packages/packages-python-pypi-27.list`
  - `deployment/dsvm_images/packages/packages-python-pypi-36.list`
  - `deployment/dsvm_images/packages/packages-python-pypi-37.list`
- If the name on `PyPI` is different from the name on `conda` (other than capitalisation) then add an entry to the `pypi-name-to-conda-name` section in `deployment/dsvm_images/packages/conda-config.json`
- If the package is not available on `conda` then add an entry to the `not-available-from-conda` section in `deployment/dsvm_images/packages/conda-config.json`
- If there are any restrictions on acceptable versions for this package (e.g. a minimum or exact version) then add an entry to the `version-requirements` section in `deployment/dsvm_images/packages/conda-config.json`
- You should also add this package to the whitelist used by Tier-3 package mirrors

**Adding a new R package**
- Add the name of the package as it appears on `CRAN` or `Bioconductor` to the appropriate package list:
  - `deployment/dsvm_images/packages/packages-r-bioconductor.list`
  - `deployment/dsvm_images/packages/packages-r-cran.list`
- If this `R` package is available as a pre-compiled apt binary (eg. `abind` is available as `r-cran-abind`) then add it to `deployment/dsvm_images/packages/packages-apt.list` if so
- You should also add this package to the whitelist used by Tier-3 package mirrors

**Adding packages to the package whitelist**
- When you add a new package to either the `PyPI` or `CRAN` whitelist you should also add all of its dependencies (and their dependencies, recursively)
- Once you have the list of packages you should add them to:
  - **PyPI:** `environment_configs/package_lists/whitelist-core-python-pypi-tier3.list`
  - **CRAN:** `environment_configs/package_lists/whitelist-core-r-cran-tier3.list`

**Changing the version of a package**
If you want to update the version of one of the packages we install from a `.deb` file (eg. `dbeaver`), you will need to edit `deployment/dsvm_images/cloud-init`
- Find the appropriate `/installation/<package name>.debinfo` section under the `write_files:` key
- Update the version number and the `sha256` hash for the file
- Check that the file naming structure still matches the format described in this `.debinfo` file

### :running: Running the image build
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `deployment/dsvm_images/setup` directory within the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Begin the provisioning and configuration of a new compute VM image using `./Provision_Compute_VM.ps1 -shmId <SHM ID>`, where the SHM ID is the one specified in the config
- The build (based on Ubuntu 18.04) takes approximately 6 hours of which 4 hours(!) is taken up with installing the Python 2.7 environment.

Once you have launched a new build by running the `./Provision_Compute_VM.ps1` script, the build will take several hours to complete.
During this time, you can monitor the build by accessing the machine using `ssh` and either reading through the full build log at `/var/log/cloud-init-output.log` or running the summary script using `/installation/analyse_build.py`.
Note that the VM will automatically shutdown at the end of the cloud-init process - if you want to analyse the build after this point, you will need to turn it back on in the Azure portal.

## :camera: Converting candidate VMs to images
Once you are happy with a particular candidate, you can convert it into an image using `./Convert_VM_To_Image.ps1`.

- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `deployment/dsvm_images/setup` directory within the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Begin the provisioning and configuration of a new compute VM image using `./Convert_VM_To_Image.ps1 -shmId <SHM ID> -vmName <VM Name>`, where the SHM ID is the one specified in the config and the VM name is the name of the virtual machine created during the provisioning step
- This will build a new image in `RG_SH_IMAGE_STORAGE` and delete the VM plus associated build artifacts (hard disk, network card and public IP address)

## :art: Registering images in the gallery
Once you have created an image, it can be registered in the image gallery using the `Register_Image_In_Gallery.ps1` script.
This must be provided with the name of the image created during the conversion step and will register this in the shared gallery as a new version of the Ubuntu-based compute machine images.
This command can take between 30 minutes and 1 hour to complete, as it has to replicate the VM across 3 different regions.

- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `deployment/dsvm_images/setup` directory within the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Begin the provisioning and configuration of a new compute VM image using `./Register_Image_In_Gallery.ps1 -shmId <SHM ID> -imageName <Image Name>`, where the SHM ID is the one specified in the config and the image name is the name of the VM image created during the conversion step
- This will register the new image in the shared image gallery and replicate it across several Azure regions.
