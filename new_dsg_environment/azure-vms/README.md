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

usage: ./build_azure_vm_image.sh [-h] [-i source_image] [-n machine_name] [-r resource_group] -s subscription
  -h                 display help
  -i source image    specify source_image: either 'Ubuntu' (default) 'UbuntuTorch' (as default but with Torch included) or 'DataScience'
  -r resource_group  specify resource group - will be created if it does not already exist (defaults to 'RG_SH_IMAGEGALLERY')
  -s subscription    specify subscription for storing the VM images [required]. (Test using 'Safe Haven Management Testing')

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
usage: register_images_in_gallery.sh -s subscription [-h] [-i source_image] [-n machine_name] [-r resource_group] [-v version_suffix]
  -h                  display help
  -i source_image     specify an already existing image to add to the gallery.
  -n machine_name     specify a machine name to turn into an image. Ensure that the build script has completely finished before running this.
  -r resource_group   specify resource group - must match the one where the machine/image already exists (defaults to 'RG_DSG_IMAGEGALLERY')
  -s subscription     specify subscription for storing the VM images [required]. (Test using 'Safe Haven Management Testing')"
  -v version_suffix   this is needed if we build more than one image in a day. Defaults to '00' and should follow the pattern 01, 02, 03 etc.
```

### Registration examples
For example, if you have recently built a compute VM using Ubuntu 18.04 as the base image, you might run a command like.

```bash
./register_images_in_gallery.sh -n GeneralizedComputeVM-Ubuntu1804Base-201812030941 -s "Safe Haven Management Testing"
```

## Creating a DSG environment
See [../azure-runbooks/Data Study Environment Build Instructions.md](DSG Build instructions).

## Safe deployment to a Turing DSG environment
VMs can be safely deployed into one of the existing Turing DSG environments using the `./deploy_compute_vm_to_turing_dsg.sh` script.
This script knows the config parameters for the existing Turing DSGs and only needs to be provided with the DSG ID, VM size and the last octet of the IP address the deployed compute VM should receive.
The IP address range available for the compute VMs in deployed DSG environemnts is `160-199`.
By convention, CPU-based VM sizes are deployed in the range `160-179` and GPU-based VM images are deployed in the range `180-199`.
For testing, the IP address can be omitted and the machine will receive a dynamic IP that is not guaranteed to be persistent across reboots.

```
usage: ./deploy_compute_vm_to_turing_dsg.sh -g dsg_group_id [-h] [-i source_image] [-x source_image_version] [-z vm_size]
  -h                        display help
  -d dsg_group_id           specify the DSG group to deploy to ('TEST' for test or 1-6 for production)
  -z vm_size                specify a VM size to use (defaults to 'Standard_DS2_v2')
  -q fixed_ip               Last part of IP address (first three parts are fixed for each DSG group)
```


## Deploying a VM from the image gallery into a DSG environment
During development, VMs can be deployed into a DSG environment using the `./deploy_azure_dsg_vm.sh` script with more granular control over configuration parameters.
However, it is strongly recommended that the core configuration parameters for each new DSG are added to the safer `./deploy_compute_vm_to_turing_dsg.sh` script as soon as the DSG environment is created, and that all compute VMs are deployed using this script instead (see section above).

```
usage: ./deploy_azure_dsg_vm.sh -s subscription_source -t subscription_target [-h] [-g nsg_name] [-i source_image] [-x source_image_version] [-n machine_name] [-r resource_group] [-u user_name]
  -h                        display help
  -g nsg_name               specify which NSG to connect to (defaults to 'NSG_Linux_Servers')
  -i source_image           specify source_image: either 'Ubuntu' (default) 'UbuntuTorch' (as default but with Torch included) or 'DataScience' (the Microsoft Azure DSVM) or 'DSG' (the current base image for Data Study Groups)
  -x source_image_version   specify the version of the source image to use (defaults to prompting to select from available versions)
  -n machine_name           specify name of created VM, which must be unique in this resource group (defaults to 'DSGYYYYMMDDHHMM')
  -r resource_group         specify resource group for deploying the VM image - will be created if it does not already exist (defaults to 'RG_DSG_COMPUTE')
  -u user_name              specify a username for the admin account (defaults to 'atiadmin')
  -s subscription_source    specify source subscription that images are taken from [required]. (Test using 'Safe Haven Management Testing')
  -t subscription_target    specify target subscription for deploying the VM image [required]. (Test using 'Data Study Group Testing')
  -v vnet_name              specify a VNET to connect to (defaults to 'DSG_DSGROUPTEST_VNet1')
  -w subnet_name            specify a subnet to connect to (defaults to 'Subnet-Data')
  -z vm_size                specify a VM size to use (defaults to 'Standard_DS2_v2')
  -m management_vault_name  specify name of KeyVault containing management secrets (required)
  -l ldap_secret_name       specify name of KeyVault secret containing LDAP secret (required)
  -j ldap_user              specify the LDAP user (required)
  -p password_secret_name   specify name of KeyVault secret containing VM admin password (required)
  -d domain                 specify domain name for safe haven (required)
  -a ad_dc_name             specify Active Directory Domain Controller name (required)
  -b ldap_base_dn           specify LDAP base DN
  -c ldap_bind_dn           specify LDAP bind DN
  -f ldap_filter            specify LDAP filter
  -q ip_address             specify a specific IP address to deploy the VM to (required)
  -y yaml_cloud_init        specify a custom cloud-init YAML script
```

Example usage

```bash
./deploy_azure_dsg_vm.sh -s "Safe Haven Management Testing" -t "Data Study Group Testing" -i Ubuntu -r RS_DSG_TEST
```

For monitoring deployments without SSH access, enable "Boot Diagnostics" for that VM through the Azure portal and then access through the serial console.
