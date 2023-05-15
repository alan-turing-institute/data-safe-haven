# Build an SRE compute image

These instructions will walk you through creating a new VM image for use in the secure research environment.

```{include} snippets/00_symbols.partial.md
:relative-images:
```

## 1. {{seedling}} Prerequisites

- An `Azure` subscription with sufficient credits to build the environment in
- `Powershell` for `Azure`
  - Install [Powershell v6.0 or above](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0)
  - Install the Azure [Powershell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0&viewFallbackFrom=azps-1.3.0)
- `SSH` or `OpenSSH` (not tested on Windows)
- SHM configuration file
  - The core properties for the environment must be present in the `environment_configs` folder as described in the {ref}`Safe Haven Management deployment instructions <deploy_shm>`.

````{hint}
If you run:

```powershell
PS> Start-Transcript -Path <a log file>
```

before you start your deployment and

```powershell
PS> Stop-Transcript
```

afterwards, you will automatically get a full log of the Powershell commands you have run.
````

### (Optional) Verify code version

If you have cloned/forked the code from our `GitHub` repository, you can confirm which version of the Data Safe Haven you are currently using by running the following commands:

![Powershell: a few seconds](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=a%20few%20seconds)

```powershell
PS> git tag --list | Select-String $(git describe --tags)
```

This will check the tag you are using against the list of known tags and print it out.
You can include this confirmation in any record you keep of your deployment.

## 2. {{gift}} (Optional) Customise the build configuration

Provisioning a VM with all the Safe Haven software is done using [cloud-init](https://cloudinit.readthedocs.io/en/latest/).
This takes a basic Ubuntu image and installs and configures all the necessary software packages.
In general, this image should cover most use cases, but it's possible that you may want to customise it for your particular circumstances, for example if you want to add a new package or to update the version of an existing package.

### Adding a new apt package

- Add the name of the package to `deployment/secure_research_desktop/packages/packages-apt.list`
- If this package adds a new executable that you would like to be available to the end user, you should also add a check for this to the end of `deployment/secure_research_desktop/cloud_init/cloud-init-buildimage-ubuntu-<version>.mustache.yaml`

````{hint}
For example, to check for `Azure Data Studio`, the following line was added:

```bash
if [ "$(which azuredatastudio)" ]; then echo "\n\n*azuredatastudio*\n\n$(which azuredatastudio)"; else echo "ERROR azuredatastudio not found!"; exit 1; fi
```
````

### Adding a new Python package

- Add the name of the package as it appears on `PyPI` to the package list:
  - `deployment/secure_research_desktop/packages/packages-python.yaml`
  - If there are any restrictions on acceptable versions for this package (e.g. a minimum or exact version) then make sure to specify this
- You should also add this package to the **allow list** used by {ref}`policy_tier_3` package mirrors in `environment_configs/package_lists/allowlist-core-python-pypi-tier3.list`

### Adding a new R package

- Add the name of the package as it appears on `CRAN` or `Bioconductor` to the appropriate package list:
  - `deployment/secure_research_desktop/packages/packages-r-bioconductor.list`
  - `deployment/secure_research_desktop/packages/packages-r-cran.list`
- If this `R` package is available as a pre-compiled apt binary (eg. `abind` is available as `r-cran-abind`) then also add it to `deployment/secure_research_desktop/packages/packages-apt.list`.
- You should also add this package to the **allow list** used by {ref}`policy_tier_3` package mirrors in `environment_configs/package_lists/allowlist-core-r-cran-tier3.list`

#### Adding packages to the package allowlist

- When you add a new package to either the `PyPI` or `CRAN` allowlist you should also determine all of its dependencies (and their dependencies, recursively)
- Once you have the list of packages you should add them to:
  - **PyPI:** `environment_configs/package_lists/allowlist-full-python-pypi-tier3.list`
  - **CRAN:** `environment_configs/package_lists/allowlist-full-r-cran-tier3.list`

### Changing the version of a package

If you want to update the version of one of the packages we install from a `.deb` file (eg. `RStudio`), you will need to edit `deployment/secure_research_desktop/cloud_init/cloud-init-buildimage-ubuntu-<version>.mustache.yaml`

- Find the appropriate `/installation/<package name>.debinfo` section under the `write_files:` key
- Update the version number and the `sha256` hash for the file
- Check that the file naming structure still matches the format described in this `.debinfo` file

## 3. {{construction_worker}} Build a release candidate

In order to provision a candidate VM you will need to do the following:

![Powershell: two to three hours](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=two%20to%20three%20hours) at {{file_folder}} `./deployment/secure_research_desktop/setup`

```powershell
PS> ./Provision_Compute_VM.ps1 -shmId <SHM ID>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SRE

```{note}
- Although the `./Provision_Compute_VM.ps1` script will finish running in a few minutes, the build itself will take several hours.
- We recommend **monitoring** the build by accessing the machine using `ssh` (the ssh info should be printed at the end of the Provision_Compute_VM.ps1 script) and either reading through the full build log at `/var/log/cloud-init-output.log` or running the summary script using `/opt/verification/analyse_build.py`.
- **NB.** You will need to connect from an approved administrator IP address
- **NB.** the VM will automatically shutdown at the end of the cloud-init process - if you want to analyse the build after this point, you will need to turn it back on in the `Azure` portal.
```

```{error}
- If you are unable to access the VM over `ssh` please check whether you are trying to connect from one of the approved IP addresses that you defined under `vmImages > buildIpAddresses` in the SHM config file.
- You can check which IP addresses are currently allowed by looking at the `AllowBuildAdminSSH` inbound connection rule in the `RG_VMIMAGES_NETWORKING > NSG_VMIMAGES_BUILD_CANDIDATES` network security group in the subscription where you are building the candidate VM
```

## 4. {{camera}} Convert candidate VM to an image

Once you are happy with a particular candidate, you can convert it into an image as follows:

![Powershell: ten minutes](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=ten%20minutes) at {{file_folder}} `./deployment/secure_research_desktop/setup`

```powershell
PS> ./Convert_VM_To_Image.ps1 -shmId <SHM ID> -vmName <VM name>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SRE
- where `<VM name>` is the name of the virtual machine created during the provisioning step

This will build a new image in `RG_VMIMAGES_STORAGE` and delete the VM plus associated build artifacts (hard disk, network card and public IP address)

```{note}
The first step of this script will run the remote build analysis script.
Please **check** that everything has built correctly before proceeding.
```

## 5. {{art}} Register image in the gallery

Once you have created an image, it can be registered in the image gallery for future use using the `Register_Image_In_Gallery.ps1` script.

![Powershell: one hour](https://img.shields.io/static/v1?style=for-the-badge&logo=powershell&label=local&color=blue&message=one%20hour) at {{file_folder}} `./deployment/secure_research_desktop/setup`

```powershell
PS> ./Register_Image_In_Gallery.ps1 -shmId <SHM ID> -imageName <Image name>
```

- where `<SHM ID>` is the {ref}`management environment ID <roles_deployer_shm_id>` for this SRE
- where `<Image Name>` is the name of the VM image created during the conversion step

This will register the image in the shared gallery as a new version of the relevant SRD image.
This command can take between 30 minutes and 1 hour to complete, as it has to replicate the VM across 3 different regions.
