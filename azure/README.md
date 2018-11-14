# Pre-requisities
In order to run `build_azure_vm_image.sh` you will need to install the Azure Command Line tools on the machine you are using.
See [here](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli) for more details about how to do this.

# Running the build script
Before running the build script, make sure you have setup the Azure cli with `az login`.
You can then run `./build_azure_vm_image.sh` without options in order to use the defaults.
The available options for configuring the base image, resource group and name of the VM can be seen by running `./build_azure_vm_image.sh -h`.
Building on top of the Data Science VM (which is itself based on Ubuntu 16.04) takes approximately 35 minutes.
Building on top of the Ubuntu VM takes approximately XX minutes.

# Examples
Build an image based off Ubuntu 18.04 called `UbuntuVM`

```bash
./build_azure_vm_image.sh -i Ubuntu -n UbuntuVM
```

Build an image based off the Microsoft Data Science VM (used by default if not specified) in the `TestBuild` resource group

```bash
./build_azure_vm_image.sh -i DataScience -r TestBuild
```