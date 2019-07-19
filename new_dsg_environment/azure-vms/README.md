# Data Safe Haven: Azure
Create VM image with full analysis environment as detailed in the [analysis environment design](https://github.com/alan-turing-institute/data-safe-haven/wiki/AnalysisEnvironmentDesign) wiki.

## Pre-requisites
In order to run `images_build_azure_compute_vm.sh` you will need to install the Azure Command Line tools on the machine you are using.
See the [Microsoft documentation](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) for more details about how to do this.

## Running the build script
Before running the build script, make sure you have setup the Azure cli with `az login`.
You can then run `./images_build_azure_compute_vm.sh`.
The available options for configuring the base image, resource group and name of the VM can be seen by running `./images_build_azure_compute_vm.sh -h`.
The build (based on Ubuntu 18.04) takes approximately 3 hours

```bash
usage: ./images_build_azure_compute_vm.sh [-h] [-s subscription] [-r resource_group] [-z vm_size]
  -h                           display help
  -s subscription              specify subscription for building the VM. (defaults to 'Safe Haven VM Images')
  -r resource_group            specify resource group - will be created if it does not already exist (defaults to 'RG_SH_BUILD_CANDIDATES')
  -z vm_size                   size of the VM to use for build (defaults to 'Standard_E16s_v3')
```

### Build examples
Build an image based off Ubuntu 18.04 called `CandidateComputeVM-Ubuntu1804Base-<date>`

```bash
./images_build_azure_compute_vm.sh -s "Safe Haven VM Images"
```

Build an image in the `TestBuild` resource group

```bash
./images_build_azure_compute_vm.sh -r TestBuild
```

## Converting candidate VMs to images
After running the build script, you should wait several hours for the build to complete.
Information about how to monitor the build using ssh is given at the end of `./images_build_azure_compute_vm.sh`.
Once you are happy with a particular candidate, you can convert it into an image using `./images_convert_azure_vm_to_image.sh.sh`.

```bash
usage: ./images_convert_azure_vm_to_image.sh [-h] -n machine_name [-s subscription] [-r resource_group_build] [-t resource_group_images]
  -h                           display help
  -n machine_name [required]   specify a machine name to turn into an image. Ensure that the build script has completely finished before running this [either this or source_image are required].
  -s subscription              specify subscription for storing the VM images. (defaults to 'Safe Haven VM Images')
  -r resource_group_build      specify resource group where the machine already exists (defaults to 'RG_SH_BUILD_CANDIDATES')
  -t resource_group_images     specify resource group where the image will be stored (defaults to 'RG_SH_IMAGE_STORAGE')
```

### Conversion example
Convert the `CandidateComputeVM-Ubuntu1804Base-201907171714` VM into an image

```bash
./images_convert_azure_vm_to_image.sh -n CandidateComputeVM-Ubuntu1804Base-201907171714
```

This will build a new image in `RG_SH_IMAGE_STORAGE` and delete the VM plus associated build artifacts (hard disk, network card and public IP address)

## Registering images in the gallery
Once you have created an image, it can be registered in the image gallery using the `./images_register_azure_image_in_gallery.sh` script.
This must be provided with the name of the image created during the conversion step and will register this in the shared gallery as a new version of the Ubuntu-based compute machine images. This command can take between 30 minutes and 1 hour to complete, as it has to replicate the VM across 3 different regions.

```bash
usage: ./images_register_azure_image_in_gallery.sh [-h] -n source_image [-s subscription] [-v version_override]
  -h                           display help
  -n source_image [required]   specify an already existing image to add to the gallery.
  -s subscription              specify subscription for storing the VM images. (defaults to 'Safe Haven VM Images')
  -v version_override          Override the automatically determined version number. Use with caution.
```

### Registration examples
For example, if you have recently built a compute VM using Ubuntu 18.04 as the base image, you might run a command like.

```bash
./images_register_azure_image_in_gallery.sh -n ImageComputeVM-Ubuntu1804Base-201907171714
```

## Creating a DSG environment
See [DSG Build instructions](../azure-runbooks/dsg_build_instructions.md).

## Safe deployment to a Turing DSG environment

### Ensure you have the required DSG-specific configuration files
Ensure you have a full configuration JSON file and `cloud-init` YAML file for the DSG environment:
  - A full JSON config file should exist at  `<data-safe-haven-repo>/new_dsg_environment/dsg_configs/full/dsg_<dsg-id>_full_config.json`
  - If one does not exist, generate one as per the instructions in section 0 of the [DSG Build instructions](../azure-runbooks/dsg_build_instructions.md)
  - A `cloud-init` YAML file should exist at `<data-safe-haven-repo>/new_dsg_environment/azure-vms/DSG_configs/cloud-init-compute-vm-DSG-<dsg-id>.yaml`.
  - If one does not exist, create one  by copying the base version at `<data-safe-haven-repo>/new_dsg_environment/azure-vms/cloud-init-compute-vm.yaml`

### Configure or log into a suitable deployment environment
To deploy a compute VM you will need the following available on the machine you run the deployment script from:
  - The [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
  - [PowerShell Core v 6.0 or above](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-6). **NOTE:** On Windows make sure to run `Windows Powershell 6 Preview` and **not** `Powershell` to run Powershell Core once installed.
- The [PowerShell Azure commandlet](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-1.3.0)
- A bash shell (via the Linux or MacOS terminal or the Windows Subsystem for Linux)

**NOTE:** You can only deploy to **one DSG at a time** from a given computer as both the `Az` CLI and the `Az` Powershell module can only work within one Azure subscription at a time. For convenience we recommend using one of the Safe Haven deployment VMs on Azure for all production deploys. This will also let you deploy compute VMs in parallel to as many DSGs as you have deployment VMs. See the [parallel deployment guide](../../azure-vms/README-parallel-deploy-using-azure-vms.md)) for details.

### Deploy a compute VM
- Navigate to the folder in the safe haven repo with the deployment scripts at `<data-safe-haven-repo>/new_dsg_environment/dsg_deploy_scripts/07_deploy_compute_vms`
- Checkout the `master` branch using `git checkout master` (or the deployment branch for the DSG environment you are deploying to - you may need to run `git fetch` first if not using `master`)
- Ensure you have the latest changes locally using `git pull`
- Ensure you are authenticated in the Azure CLI using `az login`
- Open a Powershell terminal with `pwsh`
- Ensure you are authenticated within the Powershell `Az` module by running `Connect-AzAccount` within Powershell
- Run `git fetch;git pull;git status;git log -1 --pretty="At commit %h (%H)"` to verify you are on the correct branch and up to date with `origin` (and to output this confirmation and the current commit for inclusion in the deployment record).
- Deploy a new VM into a DSG environment using the `Create_Compute_VM.ps1` script, entering the DSG ID, VM size (optional) and last octet of the desired IP address (next unused one between 160 and 199)
- After deployment, copy everything from the `git fetch;...` command and its output to the command prompt returned after the VM deployment and paste this into the deployment log (e.g. a Github issue used to record VM deployments for a DSG or set of DSGs)

### Troubleshooting Compute VM deployments
- Click on the VM in the DSG subscription under the `RG_DSG_COMPUTE` respource group. It will have the last octet of it's IP address at the end of it's name.
- Scroll to the bottom of the VM menu on the left hand side of the VM information panel
- Activate boot diagnostics on the VM and clik save. You need to stay on that screen until the activation is complete.
- Go back to the VM panel and click on the "Serial console" item near the bottom of the VM menu on the left habnd side of the VM panel.
- If you are not prompted with `login:`, hit enter until the prompt appears
- Enter `atiadmin` for the username
- Enter the password from the `dsgroup<dsg-id>-dsvm-admin-password` secret in the `dsg-mangement-<shm-id>` KeyVault in the `RG_DSG_SECRETS` respource group of the SHM subscription.
- To validate that our custom `cloud-init.yaml` file has been successfully uploaded, run `sudo cat /var/lib/cloud/instance/user-data.txt`. You should see the contents of the `new_dsg_environment/azure-vms/DSG_configs/cloud-init-compute-vm-DSG-<dsg-id>.yaml` file in the Safe Haven git repository.
- To see the output of our custom `cloud-init.yaml` file, run `sudo tail -n 200 /var/log/cloud-init-output.log` and scroll up.


## Deploying a VM from the image gallery into a DSG environment
During development, VMs can be deployed into a DSG environment using the `./deploy_azure_compute_vm.sh` script with more granular control over configuration parameters.
However, it is strongly recommended that the wrapper Powershell script `Create_Compute_VM.ps1` in `dsg_deploy_scripts/07_deploy_compute_vms` is used for this purpose, as the configuration parameters will then be loaded from the appropriate config file.

```bash
usage: ./deploy_azure_compute_vm.sh [-h] -s subscription_source -t subscription_target -m management_vault_name -l ldap_secret_name -j ldap_user -p password_secret_name -d domain -a ad_dc_name -q ip_address -e mgmnt_subnet_ip_range [-g nsg_name] [-i source_image] [-x source_image_version] [-n machine_name] [-r resource_group] [-u user_name] [-v vnet_name] [-w subnet_name] [-z vm_size] [-b ldap_base_dn] [-c ldap_bind_dn] [-f ldap_filter] [-y yaml_cloud_init ] [-k pypi_mirror_ip]
  -h                                    display help
  -s subscription_source [required]     specify source subscription that images are taken from. (Test using 'Safe Haven Management Testing')
  -t subscription_target [required]     specify target subscription for deploying the VM image. (Test using 'Data Study Group Testing')
  -m management_vault_name [required]   specify name of KeyVault containing management secrets
  -l ldap_secret_name [required]        specify name of KeyVault secret containing LDAP secret
  -j ldap_user [required]               specify the LDAP user
  -p password_secret_name [required]    specify name of KeyVault secret containing VM admin password
  -d domain [required]                  specify domain name for safe haven
  -a ad_dc_name [required]              specify Active Directory Domain Controller name
  -q ip_address [required]              specify a specific IP address to deploy the VM to
  -e mgmnt_subnet_ip_range [required]   specify IP range for safe haven management subnet
  -g nsg_name                           specify which NSG to connect to (defaults to 'NSG_Linux_Servers')
  -i source_image                       specify source_image: either 'Ubuntu' (default) 'UbuntuTorch' (as default but with Torch included) or 'DataScience' (the Microsoft Azure DSVM) or 'DSG' (the current base image for Data Study Groups)
  -x source_image_version               specify the version of the source image to use (defaults to prompting to select from available versions)
  -n machine_name                       specify name of created VM, which must be unique in this resource group (defaults to 'DSG201903161520')
  -r resource_group                     specify resource group for deploying the VM image - will be created if it does not already exist (defaults to 'RG_DSG_COMPUTE')
  -u user_name                          specify a username for the admin account (defaults to 'atiadmin')
  -v vnet_name                          specify a VNET to connect to (defaults to 'DSG_DSGROUPTEST_VNet1')
  -w subnet_name                        specify a subnet to connect to (defaults to 'Subnet-Data')
  -z vm_size                            specify a VM size to use (defaults to 'Standard_DS2_v2')
  -b ldap_base_dn                       specify LDAP base DN
  -c ldap_bind_dn                       specify LDAP bind DN
  -f ldap_filter                        specify LDAP filter
  -y yaml_cloud_init                    specify a custom cloud-init YAML script
  -k pypi_mirror_ip                     specify the IP address of the PyPI mirror (defaults to '')
```

Example usage

```bash
./deploy_azure_compute_vm.sh -s "Safe Haven Management Testing" -t "Data Study Group Testing"
```

For monitoring deployments without SSH access, enable "Boot Diagnostics" for that VM through the Azure portal and then access through the serial console.

## Deploying the mirror servers
We use a separate resource group and associated VNet to contain all of the external and internal package repository mirrors.
This can be created and deployed using `deploy_azure_external_mirror_servers.sh` and `deploy_azure_internal_mirror_servers.sh`.

### Deploy external mirrors
```
usage: ./deploy_azure_external_mirror_servers.sh [-h] -s subscription [-i vnet_ip] [-k keyvault_name] [-r resource_group]
  -h                           display help
  -s subscription [required]   specify subscription where the mirror servers should be deployed. (Test using 'Safe Haven Management Testing')
  -i vnet_ip                   specify initial IP triplet for the mirror VNet (defaults to '10.1.0')
  -k keyvault_name             specify (globally unique) name for keyvault that will be used to store admin passwords for the mirror servers (defaults to 'kv-sh-pkg-mirrors')
  -r resource_group            specify resource group - will be created if it does not already exist (defaults to 'RG_SH_PKG_MIRRORS')
```

Once the script is run, it will create external mirrors of the PyPI and CRAN package repositories.
A cronjob (3am on the 15th of each month) inside each of the external mirrors will update them from the remote repository.
A second cronjob (3am on the 1st of each month) inside each of the external mirrors will push their data to any internal mirrors that have been configured.
This ensures that the internal mirror is always between two and six weeks behind the current version of these mirrors at any time.
The VNet created when these mirrors are set up must be paired to each of the DSG environments for them to be able to use it.

Example usage:

```bash
./deploy_azure_external_mirror_servers.sh -s "Safe Haven Management Testing"
```


### Deploy an internal mirror set
```
usage: ./deploy_azure_internal_mirror_servers.sh [-h] -s subscription [-k keyvault_name] [-r resource_group] [-x name_suffix]
  -h                           display help
  -s subscription [required]   specify subscription where the mirror servers should be deployed. (Test using 'Safe Haven Management Testing')
  -k keyvault_name             specify name for keyvault that already contains admin passwords for the mirror servers (defaults to 'kv-sh-pkg-mirrors')
  -r resource_group            specify resource group that contains the external mirror servers (defaults to 'RG_SH_PKG_MIRRORS')
  -x name_suffix               specify (optional) suffix that will be used to distinguish these internal mirror servers from any others (defaults to '')
```

This script deploys a set of internal mirrors which will use an appropriate IP range inside the VNet where the external mirrors were deployed.
The internal mirrors run webservers which allow them to produce the expected behaviour of a PyPI or CRAN server.

Example usage:

```bash
./deploy_azure_internal_mirror_servers.sh -s "Safe Haven Management Testing" -x DSG1
```

### Peer DSG VNet to mirror VNet
**NOTE:** At the  moment, package mirrors are suitable for **Tier 2 and below** DSGs only.
```bash
usage: ./peer_mirrors_to_compute_vms.sh [-h] -s subscription_compute -t subscription_mirror [-g resource_group_compute] [-h resource_group_mirror] [-n vnet_name_compute] [-m vnet_name_mirror]
  -h                                   display help
  -s subscription_compute [required]   specify subscription where the compute VNet is deployed. (typically this will be 'Data Study Group Testing')
  -t subscription_mirror [required]    specify subscription where the mirror VNet is deployed. (typically this will be 'Safe Haven Management Testing')
  -c resource_group_compute            specify resource group where the compute VNet is deployed (defaults to 'RG_DSG_VNET')
  -m resource_group_mirror             specify resource group where the mirror VNet is deployed (defaults to 'RG_SH_PKG_MIRRORS')
  -v vnet_name_compute                 specify name of the compute VNet (defaults to 'DSG_DSGROUPTEST_VNet1')
  -w vnet_name_mirror                  specify name of the mirror VNet (defaults to 'VNET_SH_PKG_MIRRORS')
```

This script peers the DSG virtual network with the mirror virtual network in the management subscription so that the compute VMs can talk to the mirror servers.
Note that the "inbound on-way airlock" for packages is enforced by the NSG rules for the external and internal mirrrors.
The **external** mirror NSG rules do not allow **any inbound** communication, while permitting outbound communication to the internet (for pulling package updates from the public package servers) and it's associated internal mirrors (for pushing to these mirror servers).
The **internal** mirror NSG rules do not allow **any outbound** communication, while permitting inbound communication from their associated external mirrors (to receive pushed package updates) and from the DSGs that are peered with them (to serve packages to these DSGs).

Example usage:

```bash
./peer_mirrors_to_compute_vms.sh -s "Data Study Group Testing" "Safe Haven Management Testing"
```