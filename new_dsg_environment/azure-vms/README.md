# Data Safe Haven: Azure
Create VM image with full analysis environment as detailed in the [analysis environment design](https://github.com/alan-turing-institute/data-safe-haven/wiki/AnalysisEnvironmentDesign) wiki.

## Pre-requisites
In order to run `build_azure_vm_image.sh` you will need to install the Azure Command Line tools on the machine you are using.
See the [Microsoft documentation](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) for more details about how to do this.

## Running the build script
Before running the build script, make sure you have setup the Azure cli with `az login`.
You can then run `./build_azure_vm_image.sh`.
The available options for configuring the base image, resource group and name of the VM can be seen by running `./build_azure_vm_image.sh -h`.
Building on top of the Data Science VM (which is itself based on Ubuntu 16.04) takes approximately 1.5 hours.
Building on top of the Ubuntu VM takes approximately 3.5 hours (mostly due to building Torch).

```
usage: ./build_azure_vm_image.sh [-h] -s subscription [-i source_image] [-r resource_group] [-z vm_size]
  -h                           display help
  -s subscription [required]   specify subscription for storing the VM images. (Test using 'Safe Haven Management Testing')
  -i source_image              specify source image: either 'Ubuntu' (default) 'UbuntuTorch' (as 'Ubuntu' but with Torch included) or 'DataScience' (uses the Microsoft Data Science VM from the Azure Marketplace)
  -r resource_group            specify resource group - will be created if it does not already exist (defaults to 'RG_SH_IMAGEGALLERY')
  -z vm_size                   size of the VM to use for build (defaults to 'Standard_F2s_v2')
```

### Build examples
Build an image based off Ubuntu 18.04 (used by default if not specified) called `UbuntuVM`

```bash
./build_azure_vm_image.sh -i Ubuntu -s "Safe Haven Management Testing"
```

Build an image based off the Microsoft Data Science VM in the `TestBuild` resource group

```bash
./build_azure_vm_image.sh -i DataScience -r TestBuild -s "Safe Haven Management Testing"
```

## Registering VMs in the image gallery
After running `./build_azure_vm_image.sh` script, you should wait several hours for the build to complete.
Information about how to monitor the build using ssh is given at the end of `./build_azure_vm_image.sh`.

Once the build has finished, it can be registered in the image gallery using the `./register_images_in_gallery.sh` script.
This must be provided with the name of the machine created during the build step and will register this in the shared gallery as a new version of either the DataScience- or Ubuntu-based compute machine images. This command can take between 30 minutes and 1 hour to complete, as it has to replicate the VM across 3 different regions.

```
usage: ./register_images_in_gallery.sh [-h] -s subscription [-i source_image | -n machine_name] [-r resource_group] [-v version_suffix]
  -h                                        display help
  -s subscription [required]                specify subscription for storing the VM images . (Test using 'Safe Haven Management Testing')
  -i source_image [this or '-n' required]   specify an already existing image to add to the gallery [either this or machine_name are required].
  -n machine_name [this or '-i' required]   specify a machine name to turn into an image. Ensure that the build script has completely finished before running this [either this or source_image are required].
  -r resource_group                         specify resource group - must match the one where the machine/image already exists (defaults to 'RG_SH_IMAGEGALLERY')
  -v version_suffix                         this is needed if we build more than one image in a day. Defaults to next unused number. Must follow the pattern 01, 02, 03 etc.
```

### Registration examples
For example, if you have recently built a compute VM using Ubuntu 18.04 as the base image, you might run a command like.

```bash
./register_images_in_gallery.sh -n GeneralizedComputeVM-Ubuntu1804Base-201812030941 -s "Safe Haven Management Testing"
```

## Creating a DSG environment
At the moment this is not scripted (environments have been created by Rob). Watch this space...

## Deploying a VM from the image gallery into a DSG environment
VMs can be deployed into a DSG environment using the `./deploy_azure_dsg_vm.sh` script.
This deploys from an image stored in a gallery in `subscription_source` into a resource group in `subscription_target`.
This deployment should be into a pre-created environment, so the `nsg_name`, `vnet_name` and `subnet_name` must all exist before this script is run.

```
usage: ./deploy_azure_dsg_vm.sh [-h] -s subscription_source -t subscription_target -m management_vault_name -l ldap_secret_name -j ldap_user -p password_secret_name -d domain -a ad_dc_name -q ip_address [-g nsg_name] [-i source_image] [-x source_image_version] [-n machine_name] [-r resource_group] [-u user_name] [-v vnet_name] [-w subnet_name] [-z vm_size] [-b ldap_base_dn] [-c ldap_bind_dn] [-y yaml_cloud_init ]
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
  -g nsg_name                           specify which NSG to connect to (defaults to 'NSG_Linux_Servers')
  -i source_image                       specify source_image: either 'Ubuntu' (default) 'UbuntuTorch' (as default but with Torch included) or 'DataScience' (the Microsoft Azure DSVM) or 'DSG' (the current base image for Data Study Groups)
  -x source_image_version               specify the version of the source image to use (defaults to prompting to select from available versions)
  -n machine_name                       specify name of created VM, which must be unique in this resource group (defaults to 'DSG201902281129')
  -r resource_group                     specify resource group for deploying the VM image - will be created if it does not already exist (defaults to 'RG_DSG_COMPUTE')
  -u user_name                          specify a username for the admin account (defaults to 'atiadmin')
  -v vnet_name                          specify a VNET to connect to (defaults to 'DSG_DSGROUPTEST_VNet1')
  -w subnet_name                        specify a subnet to connect to (defaults to 'Subnet-Data')
  -z vm_size                            specify a VM size to use (defaults to 'Standard_DS2_v2')
  -b ldap_base_dn                       specify LDAP base DN
  -c ldap_bind_dn                       specify LDAP bind DN
  -y yaml_cloud_init                    specify a custom cloud-init YAML script
```

Example usage

```bash
./deploy_azure_dsg_vm.sh -s "Safe Haven Management Testing" -t "Data Study Group Testing" -i Ubuntu -r RS_DSG_TEST
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
