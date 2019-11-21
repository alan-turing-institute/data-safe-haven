# Secure Research Environment Build Instructions

# Safe Haven Management Environment Build Instructions

## Prerequisites
- An Azure subscription with sufficient credits to build the environment in
- PowerShell for Azure
  - Install [PowerShell v 6.0 or above](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0)
  - Install the Azure [PowerShell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0&viewFallbackFrom=azps-1.3.0)
- Microsoft Remote Desktop
  - On Mac this can be installed from the [apple store](https://itunes.apple.com/gb/app/microsoft-remote-desktop-10/id1295203466?mt=12)
- Azure CLI (bash)
  - Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)
- OpenSSL
  - Install using your package manager of choice
- CertBot
  - Install [Certbot](https://certbot.eff.org/). This requires using a Mac or Linux computer (or the Windows Subsystem for Linux).


### Access to required Safe Haven Management resources

- You need to be a member of the relevant "Safe Haven `<shm-id>` Admins" Security Group, where `<shm-id>` is `test` for test and `production` for production. This will give you the following access:
  - Administrative access to the relevant Safe Haven Management Azure subscription
  - Administrative access to the relevant Safe Haven Management Active Directory Domain
  - Administrative access to the relevant Safe Haven Management VMs

### Download a client VPN certificate for the Safe Haven Management VNet
  - Navigate to the Safe Haven Management (SHM) KeyVault in the Safe Haven Management subscription via `Resource Groups -> RG_SHM_SECRETS -> kv-shm-<shm-id>`.
  - Once there open the "Certificates" page under the "Settings" section in the left hand sidebar.
  - Click on the certificate named `shm-vpn-client-cert`, click on the "current version" and click the "Download in PFX/PEM format" link.
  - To install, double click on the downloaded certificate, leaving the password field blank.
  - **Make sure to securely delete the "\*.pfx" certificate file after you have installed it.**
  -  This certificate will also allow you to connect via VPN to the DSG VNet once deployed.

- #### Configure a VPN connection to the Safe Haven Management VNet
  - Navigate to the Safe Haven Management (SHM) VNet gateway in the SHM subscription via `Resource Groups -> RG_SHM_VNET -> VNET_SHM_<shm-id>_GW`, where `<shm-id>` is defined in the config file. Once there open the "Point-to-site configuration page under the "Settings" section in the left hand sidebar (see image below).
  - Click the "Download VPN client" link at the top of the page to get the root certificate (VpnServerRoot.cer) and VPN configuration file (VpnSettings.xml), then follow the [VPN set up instructions](https://docs.microsoft.com/en-us/azure/vpn-gateway/point-to-site-vpn-client-configuration-azure-cert) using the Windows or Mac sections as appropriate.
  - On Windows you may get a "Windows protected your PC" pop up. If so, click `More info -> Run anyway`
  - On Windows do not rename the vpn client as this will break it
  - Note that on OSX double clicking on the root certificate may not result in any pop-up dialogue, but the certificate should still be installed. You can view the details of the downloaded certificate by highlighting the certificate file in Finder and pressing the spacebar. You can then look for the certificate of the same name in the login KeyChain and view it's details by double clicking the list entry. If the details match the certificate has been successfully installed.

    ![image1.png](images/media/image1.png)

  - Continue to follow the set up instructions from the link above, using SSTP (Windows) or IKEv2 (OSX) for the VPN type and naming the VPN connection "Safe Haven Management Gateway (`<shm-id>`)", where `<shm-id>` is defined in the config file.

### Access to required SRE resources
- Access to a new Azure subscription which the DSG will be deployed to
  - If a subscription does not exist, create one with the name `Secure Research Environment <SRE ID> (<shm-id>)`, picking an SRE ID that is not yet in use and setting `<shm-id>` to the value given in the config file.
  - Add an initial $3,000 for test and production sandbox environments and the project specific budget for production project environments
  - Give the relevant "Safe Haven `<shm-id>` Admins" Security Group **Owner** role on the new DSG suubscription
- Access to a public routable domain name for the DSG and its name servers
  - This can be a top-level domain (eg. `dsgroup100.co.uk`) or a subdomain (eg. `testsandbox.dsgroupdev.co.uk`)
  - A DNS for this domain must exist in the `Safe Haven Domains` subscription, in the `RG_SHM_DNS_TEST` or `RG_SHM_DNS_PRODUCTION` resource group.
  - To create a new DNS zone:
    - From within the resource group click `"+" Add -> DNS Zone` and click "create"
    - Set the **Name** field to the DSG domain (i.e. `dsgroup<dsg-id>.co.uk`)
    - Click "Review + create"
    - Once deployment is finished, click "Go to resource" to view the new Azure DNS zone
    - Copy the 4 nameservers in the "NS" record to the domain's DNS record
        - if this is a top-level domain, contact whoever registered the domain
        - if this is a subdomain of an existing Azure domain (eg. `testsandbox.dsgroupdev.co.uk` then:
            - go to the DNS zone for the top-level domain in Azure
            - add a new NS record using the 4 nameservers you copied down above
            ![Subdomain NS record](images/subdomain_ns_record.png)

### Deploying multiple SREs in parallel

**NOTE:** You can only deploy to **one DSG at a time** from a given computer as both the `Az` CLI and the `Az` Powershell module can only work within one Azure subscription at a time. For convenience we recommend using one of the Safe Haven deployment VMs on Azure for all production deploys. This will also let you deploy compute VMs in parallel to as many SREs as you have deployment VMs. See the [parallel deployment guide](../azure-vms/README-parallel-deploy-using-azure-vms.md) for details.

## Build Process
[1. Define SRE configuration](#1.-Define-SRE-configuration)
[2. Prepare Safe Haven Management Domain](#2.-Prepare-Safe-Haven-Management-Domain)
[3. Deploy Virtual Network](#3.-Deploy-Virtual-Network)
[4. Deploy SRE Domain Controller](#4.-Deploy-SRE-Domain-Controller)
[5. Deploy Remote Desktop Service Environment](#5.-Deploy-Remote-Desktop-Service-Environment)
[6. Deploy Data Server](#6.-Deploy-Data-Server)
[7. Deploy Web Application Servers (Gitlab and HackMD)](#7.-Deploy-Web-Application-Servers-(Gitlab-and-HackMD))
[8. Deploy initial shared compute VM](#8.-Deploy-initial-shared-compute-VM)
[9. Apply network configuration](#9.-Apply-network-configuration)
[10. Peer SRE and package mirror networks](#10.-Peer-SRE-and-package-mirror-networks)
[11. Run smoke tests on shared compute VM](#11.-Run-smoke-tests-on-shared-compute-VM)

## 1. Define SRE configuration

The full configuration details for a new SRE are generated by defining a few "core" properties for the new SRE and the management environment in which it will be deployed.

### Core SHM configuration properties
The core properties for the relevant pre-existing Safe Haven Management (SHM) environment must be present in the `dsg_configs/core` folder.
The following core SHM properties must be defined in a JSON file named `shm_<shm-id>_core_config.json`.

**NOTE:** The `netbiosName` fields must have a maximum length of 15 characters.

```json
{
    "subscriptionName": "Name of the Azure subscription the management environment is deployed in",
    "computeVmImageSubscriptionName": "Azure Subscription name for compute VM",
    "domain": "The fully qualified domain name for the management environment",
    "netbiosname": "A short name to use as the local name for the domain. This must be 15 characters or less",
    "shmId": "A short ID to identify the management environment",
    "name": "Safe Haven deployment name",
    "organisation": {
        "name": "Organisation name",
        "townCity": "Location",
        "stateCountyRegion": "Location",
        "countryCode": "e.g. GB"
    },
    "location": "The Azure location in which the management environment VMs are deployed",
    "ipPrefix": "The three octet IP address prefix for the Class A range used by the management environment. Use 10.0.0 for this unless you have a good reason to use another prefix."
}
```

### Core SRE configuration properties

The core properties for the new SRE environment must be present in the `dsg_configs/core` folder.
The following core SRE properties must be defined in a JSON file named `dsg_<dsg-id>_core_config.json`.

```json
{
    "subscriptionName": "Name of the Azure subscription the secure research environment is deployed in",
    "dsgId": "A short ID to identify the secure research environment",
    "shmId": "The short ID for the SHM segment to deploy against",
    "tier": "The data classification tier for the SRE. This controls the outbound network restrictions on the DSG and which mirror set the DSG is peered with",
    "domain": "The fully qualified domain name for the SRE",
    "netbiosname": "A short name to use as the local name for the domain. This must be 15 characters or less. If the first part of the domain is less than 15 characters, use this for the netbiosName",
    "ipPrefix": "The three octet IP address prefix for the Class A range used by the management environemnt",
    "rdsAllowedSources": "A comma-separated string of IP ranges (addresses or CIDR ranges) from which access to the RDS webclient is permitted. For Tier 0 and 1 this should be 'Internet'. For Tier 2 this should correspond to the any organisational networks (including guest networks) at the partner organisations where access should be permitted from (i.e. any network managed by the organsiation, such as EduRoam, Turing Guest, Turing Secure etc). For Tier 3 DSGs, this should correspond to the RESTRICTED networks at the partner organisations. These should only permit connections from within meduim security access controlled physical spaces and from managed devices (e.g. Turing Secure)",
    "computeVmImageType": "The name of the Compute VM image (most commonly 'Ubuntu')",
    "computeVmImageVersion": "The version of the Compute VM image (e.g. 0.0.2019032100)"
}
```

### SRE IP Address prefix

Each SRE must be assigned it's own unique IP address space, and it is very important that address spaces do not overlap in the environment as this will cause network faults. The address spaces use a private class A range and use a 21bit subnet mask. This provides ample addresses for a SRE and capacity to add additional subnets should that be required in the future.

### Generate full configuration for SRE
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `new_dsg_environment/dsg_deploy_scripts/` folder within the Safe Haven repository.
- Generate a new full configuration file for the new DSG using the following commands.
  - `Import-Module ../../common_powershell/Configuration.psm1 -Force`
  - `Add-DsgConfig -dsgId <dsg-id>`, `<dsg-id>` is usually a number, e.g. `9` for `DSG9`)
- A full configuration file for the new SRE will be created at `new_dsg_environment/dsg_configs/full/dsg_<dsg-id>_full_config.json`. This file is used by the subsequent steps in the SRE deployment.
- Commit this new full configuration file to the Safe Haven repository

## 2. Prepare Safe Haven Management Domain

- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `new_dsg_environment/dsg_deploy_scripts/01_configure_shm_dc/` directory within the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`

### Clear out any remaining SRE data from previous deployments
**NOTE** Ensure that the SRE subscription is completely empty before running this script. If the subscription is not empty, confirm that it is not being used before deleting the resources
- Clear any remaining SRE data from the SHM by running `./Remove_SRE_Data_From_SHM.ps1 -sreId <SRE ID>`, where the SRE ID is the one specified in the config.

### Set up users and DNS
- Prepare SHM by running `./Prepare_SHM.ps1 -sreId <SRE ID>`, where the SRE ID is the one specified in the config
- This step also creates a KeyVault in the SRE subscription in `Resource Groups -> RG_SRE_SECRETS -> kv-shm-<shm-id>-sre-<SRE ID>`. Additional deployment steps will add secrets to this KeyVault and you will need to access some of these for some of the manual configiration steps later.

## 2. Deploy Virtual Network

### Create the virtual network
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `new_dsg_environment/dsg_deploy_scripts/02_create_vnet/` directory within the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Run `./Create_VNET.ps1 -sreId <SRE ID>`, where the SRE ID is the one specified in the config
- The deployment will take around 20 minutes. Most of this is deploying the virtual network gateway.
- The VNet peerings may take a few minutes to provision after the script completes.

### Set up a VPN connection to the DSG
- In the **DSG subscription** open `Resource Groups -> RG_DSG_VNET -> VNET_DSG<dsg-id>_GW`
  - Select "**Point to Site Configuration**" from the left-hand navigation
  - Download the VPN client from the "Point to Site configuration" menu
    ![VPN client](images/media/image4.png)
  - Install the VPN on your PC and test. See the [Configure a VPN connection to the Safe Haven Management VNet](#Configure-a-VPN-connection-to-the-Safe-Haven-Management-VNet) section in the [Prerequisites](#Prerequisites) list above for instructions. You can re-use the same client certificate as used for the VPN to the management VNet gateway.

## 3. Deploy SRE Domain Controller
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `new_dsg_environment/dsg_deploy_scripts/03_create_dc/` directory within the Safe Haven repository
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Run `./Setup_SRE_DC.ps1 -sreId <SRE ID>` script, where the SRE ID is the one specified in the config
- The deployment will take around 30 minutes. Most of this is running the setup scripts after creating the VM.


<!-- - Run `./Create_AD_DC.ps1 -sreId <SRE ID>` script, where the SRE ID is the one specified in the config
- The deployment will take around 20 minutes. Most of this is running the setup scripts after creating the VM.

### Configure DSG Active Directory Domain Controller
#### Upload and run remote configuration scripts
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `new_dsg_environment/dsg_deploy_scripts/03_create_dc/` directory within the Safe Haven repository
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Run `./Configure_AD_DC.ps1 -sreId <SRE ID>`, where the SRE ID is the one specified in the config
- The remote scripts will take a few minutes to return

#### Perform manual configuration steps

- Connect to the new Domain controller via Remote Desktop client over the DSG VPN connection at the IP address `<dsg-identity-subnet-prefix>.250` (e.g. 10.250.x.250)

- Login with local admin user and password for the DSG DC, which were created and stored in the `dsg<dsg-id>-dc-admin-username` and `dsg<dsg-id>-dc-admin-password` secrets in the DSG KeyVault by the DC deployment script

- From the "Server Management" application, select `Tools -> Group Policy Management`

- Expand the tree until you open the "Group Policy Objects" branch

  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML223b755.PNG](images/media/image6.png)

- Right click on "All Servers - Local Administrators" and select "Edit"

- Expand `Computer Configuration -> Policies -> Windows Settings -> Security Settings` and click on "Restricted Groups"

- Double click on "Administrators" shown under "Group Name" on the right side of the screen

- Select both of the entries in the "Members of this group" and click "Remove"

  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML2275d0c.PNG](images/media/image7.png)

- Click `Add -> Browse` and enter:

    - SG DSGROUP`<dsg-id>` Server Administrators

    - Domain Admins

- Click the "Check Names" button to resolve the names

  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML22a31c7.PNG](images/media/image8.png)

- Click `OK -> OK`. The "Administrators Properties" box will now look like this

  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML22adcec.PNG](images/media/image9.png)

- Click "OK" and close the policy window

- Right click on `Session Servers -> Remote Desktop Control` and click "Edit"

- Expand `User Configuration -> Policies -> Administrative Templates` and click "Start Menu & Taskbar"

- Double click "Start Layout" located in the right window

- Update the path shown to reflect the correct FQDN (needs changing in **two** places in the path)

  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML233aaa5.PNG](images/media/image10.png)

- Click "OK" when done and close all Group Policy windows.

- Restart the server -->

<!-- ### Create Domain Trust on SHM DC

- To enable authentication to pass from the DSG to the management active directory we need to establish a trust relationship.
- Connect to the **SHM Domain Controller** via Remote Desktop client over the VPN connection
- Login with domain user `<shm-domain>\User` and the SHM DC admin password from the `shm-dc-admin-password` secret in the Safe Haven Management KeyVault
- From the "Server Management" application, select `Tools -> Active Directory Domains and Trust`
- Right click the management domain name and select `Properties`
- Click on "Trusts" tab then click "New Trust"
  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML5eb57b.PNG](images/media/image11.png)
- Click "Next"
  | | |
  | -- | -- |
  | Trust Name:                                           | FQDN of the DSG i.e. dsgroup10.co.uk |
  | Trust Type:                                           | External Trust |
  | Direction of trust:                                   | Two-way |
  | Sides of trust:                                       | Both this domain and the specified domain |
  | User name and password:                               | Domain admin user on the DSG domain. Format: <dsg-domain\Username>. See DSG `sre-<sre-id>-dc-admin-username` and `sre-<sre-id>-dc-admin-password` secrets in the SRE KeyVault for username and password. |
  | Outgoing Trust Authentication Level-Local Domain:     | Domain-wide authentication |
  | Outgoing Trust Authentication Level-Specified Domain: | Domain-wide authentication |
- Click `Next -> Next`
  - Select "Yes, confirm the outgoing trust" -\> "Next"
  - Select "Yes, confirm the incoming trust" -\> "Next"
    ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML71798f.PNG](images/media/image12.png)
- Click "Finish" upon successful trust creation.
- Click "OK" to the informational panel on SID Filtering.
- Close the "Active Directory Domains and Trust" MMC -->

## 4. Deploy Remote Desktop Service Environment
### Create RDS VMs and perform initial configuration
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `new_dsg_environment/dsg_deploy_scripts/04_create_rds/` directory of the Safe Haven repository
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`

#### Provision the RDS VMs
- Prepare SHM by running `./Setup_SRE_RDS_Servers.ps1 -sreId <SRE ID>`, where the SRE ID is the one specified in the config
- The deployment will take around 10 minutes to complete.

<!-- #### Perform initial configuration and file transfer
- Once VM deployment is complete, run the `./Initial_Config_And_File_Transfer.ps1` script, providing the DSG ID when prompted
- This will take around 10 minutes to complete. Most of this is the transfer of files to the RDS session hosts. -->

### Install software on RDS Session Host 1 (Remote app server)
- Installing the software that will be exposed as "apps" via the remote desktop gateway is required prior to installing the RDS environment, so we install these apps on the app server session host. Installing the software required for the remote desktop server takes a long time, so we defer this to the end of the RDS set up process.
- Connect to the **RDS Session Server 1 (RDSSH1)** via Remote Desktop client over the DSG VPN connection
- Login as the admin user (eg. `sretestsandboxadmin`) where the admin username is stored in the SRE KeyVault as `sre-<sre-id>-dc-admin-username` and the password as `sre-<sre-id>-dc-admin-password` (NB. all SRE Windows servers use the same admin credentials)
- Open `C:\Installation` in Windows explorer
- Install the packages present in the folder
- **Once installed logout of the server**

### Install RDS Environment and webclient
- Connect to the **RDS Gateway** via Remote Desktop client over the DSG VPN connection
- Login as the admin user (eg. `sretestsandboxadmin`) where the admin username is stored in the SRE KeyVault as `sre-<sre-id>-dc-admin-username` and the password as `sre-<sre-id>-dc-admin-password` (NB. all SRE Windows servers use the same admin credentials)
<!-- - Login with domain user `<dsg-domain>\Username`. See DSG `dsg<dsg-id>-dc-admin-username` and `dsg<dsg-id>-dc-admin-password` secrets in DSG KeyVault for username and password. (all DSG Windows servers use the same admin credentials) -->
- Open a PowerShell command window with elevated privileges - make sure to use the `Windows PowerShell` application, not the `Windows PowerShell (x86)` application. The required server managment commandlets are not installed on the x86 version.
<!-- - Navigate to `C:\Installation` in Powershell -->

#### Install RDS environment
- Run `C:\Installation\Deploy_RDS_Environment.ps1` (prefix the command with a leading `.\` if running from within the `C:Scripts` directory)
- This script will take about 10 minutes to run

#### Install RDS webclient
- Run `Install-Module -Name PowerShellGet -Force` to update `Powershell Get` to the latest version. Enter "Y" on any prompts.
- Exit the PowerShell window and re-open a new one (with elevated permissions, making sure it is still the correct PowerShell app)
- Run `C:\Scripts\Install_Webclient.ps1` (prefix the command with a leading `.\` if running from within the `C:Scripts` directory)
- Accept any requirements or license agreements.

#### Move the session hosts under the control of the RDS gateway
- Once the webclient is installed, open Server Manager, right click on "All Servers" and select "Add Servers"
  ![Add RDS session servers to collection - Step 1](images/media/image14.png)
- Enter "rdssh" into the "Name" box and click "Find Now"
- Select the two session servers (RDSSH1, RDSSH2) and click the arrow to add them to the selected box, click "OK" to finish
  ![Add RDS session servers to collection - Step 2](images/media/image15.png)

#### Configure RDS to use SHM NPS server for client access policies
- In "Server Manager", open `Tools -> Remote Desktop Services -> Remote Desktop Gateway Manager`
  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML22da022.PNG](images/media/image21.png)
- Right click the RDS server object and select "Properties"
  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML22ed825.PNG](images/media/image22.png)
- Select "RD CAP Store" tab
- Select the "Central Server Running NPS"
- Enter the IP address of the NPS within the management domain (`10.251.0.248`)
- Set the "Shared Secret" to the value of the `dsg-<dsg-id>-nps-secret` in the DSG KeyVault.
  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML2302f1a.PNG](images/media/image23.png)
- Click "OK" to close the dialogue box.

#### Set the security groups for access to session hosts
- Expand the RDS server object and select `Policies -> Resource Authorization Policies`
- Right click on "RDG_AllDomainControllers" and select "Properties`
  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML2363efc.PNG](images/media/image24.png)
- On the "User Groups" tab click "Add"
- Click "Locations" and select the management domain
- Enter the "SG" into the "Enter the object names to select" box and click on "Check Names" select the correct "Research Users" security group from the list i.e. SG DSGROUP`<dsg-id>` Research Users.
  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML238cb34.PNG](images/media/image25.png)
- Click "OK" and the group will be added to the "User Groups" screen
  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML23aa4c7.PNG](images/media/image26.png)
- Click "OK" to exit the dialogue box
- Right click on "RDG_RDConnectionBrokers" policy and select "Properties"
  ![C:\\Users\\ROB\~1.CLA\\AppData\\Local\\Temp\\SNAGHTML23c2d0d.PNG](images/media/image27.png)
- Repeat the process you did for the "RDG_AllDomainComputers" policy and add the correct Research Users security group.

#### Increase the authorisation timeout to allow for MFA
- In "Server Manager", select `Tools -> Network Policy Server`
- Expand `NPS (Local) -> RADIUS Clients and Servers -> Remote RADIUS Servers` and double click on `TS GATEWAY SERVER GROUP`
  ![](images/media/rds_local_nps_remote_server_selection.png)
- Highlight the server shown in the “RADIUS Server” column and click “Edit”
- Change to the “Load Balancing” tab and change the parameters to match the screen below
    ![](images/media/rds_local_nps_remote_server_timeouts.png)
- Click “OK” twice and close “Network Policy Server” MMC

### Configuration of SSL on RDS Gateway
- Ensure you have [Certbot](https://certbot.eff.org/) installed. This requires using a Mac or Linux computer.
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `new_dsg_environment/dsg_deploy_scripts/04_create_rds/` directory of the Safe Haven repository
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Run the `./Generate_New_Ssl_Cert.ps1` script, providing the DSG ID when prompted.
- **NOTE:** Let's Encrypt will only issue **5 certificates per week** for a particular host (e.g. `rds.dsgroupX.co.uk`). For production environments this should usually not be an issue. However, if you find yourself needing to re-run this step, either to debug an error experienced in production or when redeploying a test environment frequently during development, you should run `./Generate_New_Ssl_Cert.ps1 -testCert $true` to use the Let's Encrypt staging server, which will issue certificates more frequently. However, these certificates will not be trusted by your browser, so you will need to override the security warning in your browser to access the RDS web client for testing.

### Test RDS deployment
- Connect to the **SHM Domain Controller** via Remote Desktop client over the VPN connection
- Login with **SHM** domain user `<shm-domain>\User` See **SHM** `dsg<dsg-id>-dc-admin-username` and `shm-dc-admin-password` secrets in the **SHM** KeyVault for username and password.
- In the "Server Management" app, click `Tools -> Active Directory Users and Computers`
- Open the `Safe Haven Security Groups` OU
- Right click the `SG DSGROUP<dsg-id> Research Users` security group and select "Properties"
- Click on the "Members" tab and click the "Add" button
- Enter the start of your name and click "Check names"
- Select your name and click "Ok"
- Click "Ok" again to exit the add users dialogue
- Launch a local web browser and go to `https://rds.<dsg-domain>/RDWeb/webclient/` and log in. If you get an "unexpected server authentication certificate error", your browser has probably cached a previous certificate for this domain. Do a [hard reload](https://www.getfilecloud.com/blog/2015/03/tech-tip-how-to-do-hard-refresh-in-browsers/) of the page (permanent fix) or open a new private / incognito browser window and visit the page.
- Once you have logged in, double click on the "Presentation server" app icon. You should receive an MFA request to your phone or authentication app. Once you have approved the sign in, you should see a remote Windows desktop.
- If you get a "404 resource not found" error when accessing the webclient URL, but get an IIS landing page when accessing `https://rds.<dsg-domain>`, it is likely that you missed the step of installing the RDS webclient.
    - Go back to the previous section and run the webcleint installation step.
    - Once the webclient is installed, you will need to manually run the steps from the SSL certificate generation script to install the SSL certificate on the  webclient. Still on the RDS Gateway, run the commands below, replacing `<path-to-full-certificate-chain>` with the path to the `xxx_full_chain.pem` file in the `C:\Certificates` folder.
        - `Import-RDWebClientBrokerCert <path-to-full-certificate-chain>`
        - `Publish-RDWebClientPackage -Type Production -Latest`
- If you can log in to the initial webclient authentication but don't get the MFA request, then the issue is likely that the configuration of the connection between the SHM NPS server and the RDS Gateway server is not correct.
    - Ensure that the SHM NPS server RADIUS Client configuration is using the **private** IP address of the RDS Gateway and **not** its public one.
    - Ensure the same shared secret from the `dsg-<dsg-id>-nps-secret` in the DSG KeyVault is used in **both** the SHM NPS server RADIUS Client configuration and the DSG RDS Gateway RD CAP Store configuration (see previous sections for instructions).
- If you get a "We couldn't connect to the gateway because of an error" message, it's likely that the "Remote RADIUS Server" authentication timeouts have not been increased as described in a previous section. It seems that these are reset everytime the "Central CAP store" shared RADIUS secret is changed.
- If you get multiple MFA requests with no change in the "Opening ports" message, it may be that the shared RADIUS secret does not match on the SHM server and DSG RDS Gateway. It is possible that this may occur if the password is too long. We previously experienced this issue with a 20 character shared secret and this error went away when we reduced the length of the secret to 12 characters. We then got a "We couldn't connect to the gateway because of an error" message, but were then able to connect successfully after again increasing the authorisation timeout for the remote RADIUS server on the RDS Gateway.
- **NOTE:** The other apps will not work until the other servers have been deployed.

### Install software on RDS Session Host 2 (Presentation server / Remote desktop server)
- Connect to the **RDS Session Server 2 (RDSSH1)** via Remote Desktop client over the DSG VPN connection
- Login with domain user `<dsg-domain>\Username`. See DSG `dsg<dsg-id>-dc-admin-username` and `dsg<dsg-id>-dc-admin-password` secrets in DSG KeyVault for username and password (all DSG Windows servers use the same admin credentials)
- Open `C:\Software` in Windows explorer
- Install the packages present in the folder
- **NOTE:** Installing TexLive (`install-tl-windows-xxx`) will take about an hour to install (including downloading lots of files from the internet), so it is recommended to leave this until last and then continue with the remaining sections of this runbook while the TexLive installation completes.
- Once installed logout of the server

## 5. Deploy Data Server
### Create Dataserver VM
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `new_dsg_environment/dsg_deploy_scripts/05_create_dataserver/` directory in the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Run the `./Create_Data_Server.ps1` script, providing the DSG ID when prompted.
- The deployment will take around 10 minutes to complete

### Configure Dataserver
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `new_dsg_environment/dsg_deploy_scripts/05_create_dataserver/` directory in the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Run the `./Configure_Data_Server.ps1` script, providing the DSG ID when prompted.

## 6. Deploy Web Application Servers (Gitlab and HackMD)
- Note: Before deploying the Linux Servers ensure that you've allowed GitLab Community Edition to be programmatically deployed within the Azure Portal.
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Open a Powershell terminal and navigate to the `new_dsg_environment/dsg_deploy_scripts/06_create_web_application_servers/` directory of the Safe Haven repository.
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Run the `./Create_Web_App_Servers.ps1` script, providing the DSG ID when prompted
- The deployment will take a few minutes to complete

### Configure GitLab Server
- GitLab is fully configured by the `Create_Web_App_Servers.ps1` deployment script
- There is a built-in `root` user, whose password is stored in the DSG KeyVault (see DSG config file for KeyVault and secret names).
- You can test Gitlab independently of the RDS servers by connecting to `<dsg-subnet-data-prefix>.151` and logging in with the full `username@<shm-domain-fqdn>` of a user in the `SG DSGROUP<dsg-id> Research Users` security group.

### Configure HackMD Server
- HackMD is fully configured by the `Create_Web_App_Servers.ps1` deployment script
- You can test HackMD independently of the RDS servers by connecting to `<dsg-subnet-data-prefix>.152:3000` and logging in with the full `username@<shm-domain-fqdn>` of a user in the `SG DSGROUP<dsg-id> Research Users` security group.

## 7. Deploy initial shared compute VM

### [OPTIONAL] Create a custom cloud init file for the DSG if required
  - By default, compute VM deployments will use the `cloud-init-compute-vm-DEFAULT.yaml` configuration file in the `<data-safe-haven-repo>/new_dsg_environment/dsg_configs/cloud_init/` folder. This does all the necessary steps to configure the VM to work with LDAP log on etc.
  - If you require additional steps to be taken at deploy time while the VM still has access to the internet (e.g. to install some additional project-specific software), copy the default cloud init file to a file named `cloud-init-compute-vm-DSG-<dsg-id>.yaml` in the same folder and add any additional required steps in the `DSG-SPECIFIC COMMANDS` block marked with comments.

### Configure or log into a suitable deployment environment
To deploy a compute VM you will need the following available on the machine you run the deployment script from:
  - The [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli)
  - [PowerShell Core v 6.0 or above](https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell?view=powershell-6). **NOTE:** On Windows make sure to run `Windows Powershell 6 Preview` and **not** `Powershell` to run Powershell Core once installed.
- The [PowerShell Azure commandlet](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-1.3.0)
- A bash shell (via the Linux or MacOS terminal or the Windows Subsystem for Linux)

### Deploy a compute VM
- Navigate to the folder in the safe haven repo with the deployment scripts at `<data-safe-haven-repo>/new_dsg_environment/dsg_deploy_scripts/07_deploy_compute_vms`
- Checkout the `master` branch using `git checkout master` (or the deployment branch for the DSG environment you are deploying to - you may need to run `git fetch` first if not using `master`)
- Ensure you have the latest changes locally using `git pull`
- Ensure you are authenticated in the Azure CLI using `az login` and then checking this has worked with `az account list`
- Open a Powershell terminal with `pwsh`
- Ensure you are authenticated within the Powershell `Az` module by running `Connect-AzAccount` within Powershell
- Run `git fetch;git pull;git status;git log -1 --pretty="At commit %h (%H)"` to verify you are on the correct branch and up to date with `origin` (and to output this confirmation and the current commit for inclusion in the deployment record).
- Deploy a new VM into a DSG environment using the `./Create_Compute_VM.ps1` script, entering the DSG ID, VM size (optional) and last octet of the desired IP address.
  - The initial shared VM should be deployed with the last octet `160`
  - The convention is that subsequent CPU-based VMs are deployed with the next unused last octet in the range `161` to `179` and GPU-based VMs are deployed with the next unused last octet between `180` and `199`.
- After deployment, copy everything from the `git fetch;...` command and its output to the command prompt returned after the VM deployment and paste this into the deployment log (e.g. a Github issue used to record VM deployments for a DSG or set of DSGs)

### Troubleshooting Compute VM deployments
- Click on the VM in the DSG subscription under the `RG_DSG_COMPUTE` respource group. It will have the last octet of it's IP address at the end of it's name.
- Scroll to the bottom of the VM menu on the left hand side of the VM information panel
- Activate boot diagnostics on the VM and click save. You need to stay on that screen until the activation is complete.
- Go back to the VM panel and click on the "Serial console" item near the bottom of the VM menu on the left habnd side of the VM panel.
- If you are not prompted with `login:`, hit enter until the prompt appears
- Enter the username from the `dsg<dsg-id>-dsvm-admin-password` secret in the DSG KeyVault.
- Enter the password from the `dsg<dsg-id>-dsvm-admin-password` secret in the DSG KeyVault.
- To validate that our custom `cloud-init.yaml` file has been successfully uploaded, run `sudo cat /var/lib/cloud/instance/user-data.txt`. You should see the contents of the `new_dsg_environment/azure-vms/DSG_configs/cloud-init-compute-vm-DSG-<dsg-id>.yaml` file in the Safe Haven git repository.
- To see the output of our custom `cloud-init.yaml` file, run `sudo tail -n 200 /var/log/cloud-init-output.log` and scroll up.

## 8. Apply network configuration
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Change to the `new_dsg_environment/dsg_deploy_scripts/08_apply_network_configuration/` directory of the Safe Haven repository
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Run the `./Apply_Network_Configuration.ps1` script, providing the DSG ID when prompted

## 09. Unpeering DSG and package mirror networks
The `Apply_Network_Configuration.ps1` script in section 8 now ensures that the DSG is peered to the correct mirror network by running `new_dsg_environment/dsg_deploy_scripts/09_mirror_peerings/Configure_Mirror_Peering.ps1` as part of its execution.

**==THESE SCRIPTS SHOULD NOT BE MANUALLY RUN WHEN DEPLOYING A DSG OR UPDATING ITS CONFIGURATION==**
However, if you need to unpeer the mirror networks for some reason (e.g. while preparing a DSG subscription for re-use), you can run the unpeering script separately as described below.
- Ensure you have the latest version of the Safe Haven repository from [https://github.com/alan-turing-institute/data-safe-haven](https://github.com/alan-turing-institute/data-safe-haven).
- Change to the `new_dsg_environment/dsg_deploy_scripts/09_mirror_peerings/internal/` directory of the Safe Haven repository
- Open a PowerShell environment by typing `pwsh` on the Ubuntu bash command line
- Ensure you are logged into Azure within PowerShell using the command: `Connect-AzAccount`
- Run the `./Unpeer_Dsg_And_Mirror_Networks.ps1` script, providing the DSG ID when prompted

## 10. Run smoke tests on shared compute VM
These tests should be run **after** the network lock down and peering the DSG and mirror VNets.

To run the smoke tests:

- Ensure you have the appropriate version of the tests by changing to the `master` branch (or the branch you deployed the VMs from if different) and doing a `pull` from Git or your preferred Git app (e.g. SourceTree).
- Connect to the **DSG Dataserver** via Remote Desktop client over the DSG VPN connection. Ensure that the Remote Desktop client configuration shares the Safe Haven repository folder on your local machine with the  Dataserver (or you have another way to transfer files between your local machine and the Dataserver VM).
- Login with domain user `<dsg-domain>\Username`. See DSG `dsg<dsg-id>-dc-admin-username` and `dsg<dsg-id>-dc-admin-password` secrets in DSG KeyVault for username and password (all DSG Windows servers use the same admin credentials)
- Copy the `package_lists` and `tests` folders from your local `<safe-haven-repository>/new_dsg_environment/azure-vms/` folder to a `dsg_tests` folder on within the `F:\Data` folder on the DSG Dataserver.
    ![](images/media/transfer_test_files_to_dataserver.png)
- Connect to the DSG environment via the RDS Webclient at `https://rds.dsgroup<dsg-id>.co.uk/RDWeb/webclient`, logging in as a normal Research User.
- Open the WinSCP "File transfer" app and connect to the IP address of the Shared VM (`<data-subnet-prefix>.160`) with the same credentials.
- Copy the `dsg_tests` folder from the Dataserver `R:\` drive to your home directory on the Shared VM.
  ![](images/media/copy_test_files_from_dataserver_to_shared_vm.png)
- Connect to a **remote desktop** on the Shared VM using the "Shared VM (Desktop)" app
- Open a terminal session
- Change to the tests folder using `cd ~/dsg_tests/tests`
- Follow the instructions in the `README.md` file the `tests` folder in your local copy of the `<safe-haven-repository>/new_dsg_environment/azure-vms/` folder.
- If all test results are expected you are done! Otherwise, contact REG for help diagnosing test failures.

## Server list
- The following servers are created as a result of these instructions:
  - DSG`<dsg-id>`DC (domain controller)
  - DATASERVER
  - HACKMD
  - GITLAB
  - RDS
  - RDSSH1
  - RDSSH2
  - An initial shared compute VM (at IP address `<data-subnet-prefix>.160`)
