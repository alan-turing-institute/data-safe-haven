# Data Safe Haven: Azure
Create VM image with full analysis environment as detailed [here](https://github.com/alan-turing-institute/data-safe-haven/wiki/AnalysisEnvironmentDesign)

## Pre-requisities
In order to run `build_azure_vm_image.sh` you will need to install the Azure Command Line tools on the machine you are using.
See [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) for more details about how to do this.

## Running the build script
Before running the build script, make sure you have setup the Azure cli with `az login`.
You can then run `./build_azure_vm_image.sh` without options in order to use the defaults.
The available options for configuring the base image, resource group and name of the VM can be seen by running `./build_azure_vm_image.sh -h`.
Building on top of the Data Science VM (which is itself based on Ubuntu 16.04) takes approximately 35 minutes.
Building on top of the Ubuntu VM takes approximately 2.5 hours (mostly due to building Torch).

### Build examples
Build an image based off Ubuntu 18.04 called `UbuntuVM`

```bash
./build_azure_vm_image.sh -i Ubuntu -n UbuntuVM
```

Build an image based off the Microsoft Data Science VM (used by default if not specified) in the `TestBuild` resource group

```bash
./build_azure_vm_image.sh -i DataScience -r TestBuild
```

## Creating a VM using the Data Safe Haven image
At the end of the output from the `./build_azure_vm_image.sh` script, information about how to create a VM based on the image will be printed.
This will use the `vm create` command from Azure Command Line tools and will look something like the following:

```bash
az vm create --resource-group <NAME_OF_RESOURCE_GROUP_CONTAINING_IMAGE> --name <VM_NAME> --image <NAME_OF_CREATED_IMAGE> --admin-username azureuser --generate-ssh-keys
```

If the image was built using the Microsoft Data Science VM, some additional `--plan` options will be needed that are also printed out in the output from this script.

NB. These images will need to be copied to the target subscription in order to be deployable there.