

## Make a new deployment VM
### Create a new Azure VM
- Log into the Azure portal
- Click on the VM icon in the left hand sidebar
- Click on the "+" icon in the pane header to add a VM
- Base on Ubuntu 18.04 LTS
- Create in the "Safe Haven Management Testing" subscription
- Create in the "VM-Deployment-Pool" Resource Group
- Use region "West Europe"
- Name the VM `SH-DEPLOYMENT-0X`(replacing `0X` a zero padded number one greater than largest one currently used by an existing deployment VM)
- Set the username to "atiadmin"
- Set the password from the `deployment-vm-admin-password` secret in `dsg-management-test` KeyVault in the `RG_DSG_SECRETS` resource group of the `Safe Haven Management Testing` subscription
- Open port 22 in the network settings at the bottom of the initial "Basic" configuration tab
- Select "Review + deploy"
- Deploy the VM
- Wait for deployment to complete
- Navigate to the VM in the portal, select the "Networking" option in the left hand sidebar and add the following **inbound** rule for [mosh](https://mosh.org/) 
  - Name: `mosh`
  - Source: `Any`
  - Source port ranges: `*`
  - Destination: `Virtual network`
  - Destination port ranges: `60000-61000`
  - Protocol: `UDP`
  - Action: `Allow`
  - Priority: `310`

### Install the latest Azure CLI
- Connect to the VM using `ssh atiadmin@sh-deployment-0X.westeurope.cloudapp.azure.com` (replacing `0X` with the zero padded number of the deployment VM you want to use and using the password from the `deployment-vm-admin-password` secret in `dsg-management-test` KeyVault in the `RG_DSG_SECRETS` resource group of the `Safe Haven Management Testing` subscription)
- Install [mosh](https://mosh.org/) for more stable SSH via `sudo apt-get install mosh -y`
- Install pip via `sudo apt install python-pip -y`
- Install the Azure CLI via `pip2 install azure-cli` (system python is 2.7)
- You may need to logout of the SSH session and log in again to get `pip2` working.
- Test you can run the Azure CLI with `az`. This should print an extensive help screen.
- You may need to logout of the SSH session and log in again to get the `az` command to work
- Generate a new SSH key to authorise to read from the Safe Haven repo on Github via `ssh-keygen -t rsa -b 4096`
- Print the **public** part of the keypair to the console using `cat ~/.ssh/id_rsa.pub`
- Add this as a deploy key from the configuration tab of the safe haven repo on Github (**do not** check the "Allow write access" box - these VMs only need read access) 
- Clone the safe haven repo via `git clone git@github.com:alan-turing-institute/data-safe-haven.git`. This will automatically authenticate using the VM's `id_rsa` SSH key you just created and added to the safe haven repo as a deploy key.

### Install Poweshell with Azure module
- Install Powershell Core. The following are taken from the Microsoft Powershell Core [installation instructions for Linux](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-6)
  ```bash
  # Download the Microsoft repository GPG keys
  wget -q https://packages.microsoft.com/config/ubuntu/14.04/packages-microsoft-prod.deb

  # Register the Microsoft repository GPG keys
  sudo dpkg -i packages-microsoft-prod.deb

  # Update the list of products
  sudo apt-get update

  # Install PowerShell
  sudo apt-get install -y powershell
  ```

- Install the `Az` Powershell module
  - Start Powershell with `pwsh`
  - Within Powershell run `Install-Module -Name Az -AllowClobber`                              
## Use a deployment VM to deploy to the Safe Haven
The VM(s) you want to use may be stopped to save money, so you may need to start the VM(s) you want to use from the Azure Portal
- Install [mosh](https://mosh.org/) locally for more stable SSH (e.g. via `brew install mosh` on OSX)
- Connect to the VM using `mosh atiadmin@sh-deployment-0X.westeurope.cloudapp.azure.com` (replacing `0X` with the zero padded number of the deployment VM you want to use and using the password from the `deployment-vm-admin-password` secret in `dsg-management-test` KeyVault in the `RG_DSG_SECRETS` resource group of the `Safe Haven Management Testing` subscription)
- Navigate to the folder in the safe haven repo with the deployment scripts using `cd data-safe-haven/new_dsg_environment/azure-vms/`
- Checkout the master branch using `git checkout master`
- Ensure you have the latest changes locally using `git pull`
- Ensure you are authenticated in the Azure CLI using `az login`
- Deploy a new VM into a DSG environment using the `deploy_compute_vm_to_turing_dsg.sh` script

