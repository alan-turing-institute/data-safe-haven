# Safe Haven Management Environment Build Instructions

## Prerequisites
An already-existing management segment (instructions about how to build one will come here...)

## 0 Package mirrors
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).

- Ensure you are authenticated in the Azure CLI using `az login` and then checking this has worked with `az account list`

- Open a Powershell terminal with `pwsh` and navigate to the `new_dsg_environment/shm_deploy_scripts/00_deploy_package_mirrors/` directory within the Safe Haven repository.

- Ensure you are logged into the Azure within PowerShell using the command: `Connect-AzAccount`

- Ensure the active subscription is set to that you are using for the new SAE using the command: `Set-AzContext -SubscriptionId "<dsg-subscription-name>"`

## 0.1 Deploy package mirrors
- Run the `./Create_Package_Mirrors.ps1` script, providing the DSG ID when prompted. This will set up mirrors for the tier corresponding to that DSG. If some DSGs use Tier-2 mirrors and some use Tier-3 you will have to run this multiple times. You do not have to run it more than once for the same tier (eg. if there are two DSGs which are both Tier-2, you only need to run the script for one of them).

## 0.1 Tear down package mirrors
- Run the `./Teardown_Package_Mirrors.ps1` script, providing the DSG ID when prompted. This will remove all the mirrors for the tier corresponding to that SAE. **NB. This will remove the mirrors from all SAEs of the same tier.**
