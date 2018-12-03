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

```
usage: build_azure_vm_image.sh [-h] [-i source_image] [-n machine_name] [-r resource_group] [-s subscription]
    -h                 display help"
    -i source_image    specify source_image: either 'Ubuntu' (default) or 'DataScience'"
    -r resource_group  specify resource group - will be created if it does not already exist (defaults to 'RG_DSG_IMAGEGALLERY')"
    -s subscription    specify subscription for storing the VM images (defaults to 'Safe Haven Management Testing')"
```

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

```
usage: register_images_in_gallery.sh [-h] [-i source_image] [-n machine_name] [-s subscription] [-v version_suffix]
  -h                  display help
  -i source_image     specify an already existing image to add to the gallery.
  -n machine_name     specify a machine name to turn into an image. Ensure that the build script has completely finished before running this.
  -r resource_group   specify resource group - must match the one where the machine/image already exists (defaults to 'RG_DSG_IMAGEGALLERY')
  -s subscription     specify subscription for storing the VM images (defaults to 'Safe Haven Management Testing')
  -v version_suffix   this is needed if we build more than one image in a day. Defaults to '00' and should follow the pattern 01, 02, 03 etc.
```

### Registration examples
For example, if you have recently built a compute VM using Ubuntu 18.04 as the base image, you might run a command like. 

```bash
./register_images_in_gallery.sh -n GeneralizedComputeVM-Ubuntu1804Base-201812030941
```

## Deploying a VM from the image gallery
VMs can be deployed into a DSG environment using the `./deploy_azure_dsg_vm.sh` script.
At the moment this does not deploy into a correctly set up environment (eg. with NSG rules/VNETs etc.).
This may be separated into two scripts in future - one to set up a new environment and one to deploy VMs into it.