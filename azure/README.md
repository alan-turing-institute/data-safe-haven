# Data Safe Haven: Azure
Create VM image with full analysis environment as detailed in the [analysis environment design](https://github.com/alan-turing-institute/data-safe-haven/wiki/AnalysisEnvironmentDesign) wiki.

## Pre-requisites
In order to run `build_azure_vm_image.sh` you will need to install the Azure Command Line tools on the machine you are using.
See the [Microsoft documentation](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) for more details about how to do this.

## Running the build script
Before running the build script, make sure you have setup the Azure cli with `az login`.
You can then run `./build_azure_vm_image.sh` without options in order to use the defaults.
The available options for configuring the base image, resource group and name of the VM can be seen by running `./build_azure_vm_image.sh -h`.
Building on top of the Data Science VM (which is itself based on Ubuntu 16.04) takes approximately 1.5 hours.
Building on top of the Ubuntu VM takes approximately 3.5 hours (mostly due to building Torch).

### Build examples
Build an image based off Ubuntu 18.04 (used by default if not specified) called `UbuntuVM`

```bash
./build_azure_vm_image.sh -i Ubuntu
```

Build an image based off the Microsoft Data Science VM in the `TestBuild` resource group

```bash
./build_azure_vm_image.sh -i DataScience -r TestBuild
```

## Registering VMs in the image gallery
After running `./build_azure_vm_image.sh` script, you should wait several hours for the build to complete.
Information about how to monitor the build using ssh is given at the end of `./build_azure_vm_image.sh`.

Once the build has finished, it can be registered in the image gallery using the `./register_images_in_gallery.sh` script.
This must be provided with the name of the machine created during the build step and will register this in the shared gallery as a new version of either the DataScience- or Ubuntu-based compute machine images. This command can take between 30 minutes and 1 hour to complete, as it has to replicate the VM across 3 different regions.

```bash
./register_images_in_gallery.sh -n GeneralizedComputeVM-Ubuntu1804Base-201812030941
```

## Deploying a VM from the image gallery
VMs can be deployed into a DSG environment using the `./deploy_azure_dsg_vm.sh` script.
This may be separated into two scripts in future - one to set up a new environment and one to deploy VMs into it.