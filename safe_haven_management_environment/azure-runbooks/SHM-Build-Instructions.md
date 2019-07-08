# Safe Haven Management Environment Build Instructions

## Prerequisites

### An Azure subscription with sufficient credits to build the environment in 

### Install and configure PowerShell for Azure
  - Install [PowerShell v 6.0 or above](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0)
  - Install the Azure [PowerShell Module](https://docs.microsoft.com/en-us/powershell/azure/install-az-ps?view=azps-2.2.0&viewFallbackFrom=azps-1.3.0)

### Microsoft Remote Desktop
- On Mac this can be installed from the [apple store](https://itunes.apple.com/gb/app/microsoft-remote-desktop-10/id1295203466?mt=12)

### Azure CLI 
- Install the [Azure CLI](https://docs.microsoft.com/en-us/cli/azure/install-azure-cli?view=azure-cli-latest)

### Docker desktop
- Install [Docker Desktop](https://www.docker.com/products/docker-desktop). Docker is used to generate certificates. 

## 0. Setup Azure Active Directory (AAD) with P1 Licenses

### Create a new AAD
1. Login to the [Azure Portal](https://azure.microsoft.com/en-gb/features/azure-portal/)
2. Click `Create a Resource`  and search for `Azure Active Directory`
3. Set the "Organisation Name" to `<organisation> Safe Haven <environment>`, e.g. `Turing Safe Haven Test B"
4. Set the "Initial Domain Name" to the "Organisation Name" all lower case with spaces removed
5 Set the "Country or Region" to "UK South"
4. Click Create AAD

![](images/AAD.png)

### Create a Custom Domain Name 
#### Create a DNS zone for the custom domain
1. For Turing SHMs, create a new DNS Zone for a subdomain under the `turingsafehaven.ac.uk` domain (for the `production` environment - within the `Safe Haven Managment` subscription) or under the `dsgroupdev.co.uk` domain (for the `test` environment  - within the `Safe Haven Management Testing` subscription). For safe havens hosted by other organisations, follow their guidance. This may require purchasing a dedicated domain.
2. Whatever new domain or subdomain you choose, you must create a new Azure DNS Zone for the domain or subdomain.
    - Click `Create a resource` in the far left menu, seach for "DNS Zone" and click "Create.
    - Select the management subscription created for this managment deployment and select or create the `RG_SHM_DNS` resource group.
    - For the `Name` field enter the fully qualified domain / subdomain (e.g. `testb.dsgroupdev.co.uk` for a second test SHM deployed as part of the Turing `test` environment).
3. Once deployed, duplicate the `NS` record in the DNS Zone for the new domain / subdomain to it's parent record in the DNS system.
    - Navigate to the new DNS Zone (click `All resources` in the far left panel and seach for "DNS Zone". The NS record will lists 4 Azure name servers.
        - If using a subdomain of an existing Azure DNS Zone, create an NS record in the parent Azure DNS Zone for the new subdomain with the same value as the NS record in the new Azure DNS Zone for the subdomain (i.e. for a new subdomain `testb.turingsafehaven.ac.uk`, duplicate its NS record to the Azure DNS Zone for `dsgroupdev.co.uk`, under the name `testb`).
       - If using a new domain, create an NS record in at the registrar for the new domain with the same value as the NS record in the new Azure DNS Zone for the domain.
  

## Add the custom domain to the new AAD 
1. Once the new AAD and custom domain have been created, ensure your Azure Portal session is using the new AAD directory. The name of the current directory is under your username in the top right corner of the Azure portal screen. To change directories click on your username at the top right corner of the screen, then `Switch directory`, then the name of the new AAD directory.
2. Click `Active directory` in the far left panel then `Custom domain names` in the left hand panel
3. Note the DNS record details displayed
  ![AAD DNS record details](images/aad_dns_record_details.png)
3. In a separate Azure portal window, navigate to the DNS Zone for your custom domain and create a new record using the details provided (the `@` goes in the `Name` field and the TTL of 36000 is in seconds)
  ![Create AAD DNS Record](images/create_aad_dns_record.png)
4. Navigate back to the custom domain creation screen in the new AAD and click "Verify"

### Add additional administrators
The User who creates the AAD will automatically have the Global Administrator (GA) Role (Users with this role have access to all administrative features in Azure Active Directory). Additional users require this role to prevent this person being a single point of failure.

1. Ensure your Azure Portal session is using the new Safe Haven Management (SHM) AAD directory. The name of the current direcotty is under your username in the top right corner of the Azure portal screen. To change directories click on your username at the top right corner of the screen, then `Switch directory`, then the name of the new SHM directory.
2. On the left hand panel click `Azure Active Directory`.
3. Navigate to `Users` and **either**:
    - If your administrators already exist in an external AAD you trust (e.g. one managing access to the subscription you are deploying the SHM into), add each user by clicking `+ New guest user` and entering their external email address. For the Turing, add all users in the "Safe Haven `<environment>` Admins" group in the Turing corporate AAD as they all have Owner rights on all Turing safe haven subscriptions.
    - If you are creating local users, set their usernames to `firstname.lastname@customdomain`, using the custom domain you set up in the earlier step.
5. Click on each user and then on `Directory role` in the left sidebar click `Add assignment` and search for "Global Administrator", select this role and click `Add`.
7. To enable MFA, purchase sufficient P1 licences and add them to all the new users. Note you will also need P1 licences for standard users accessing the Safe Haven.
   - **For testing only**, you can enable a free trial of the P2 License (NB. It can take a while for these to appear on your AAD)
   - To add licenses to a user click `licenses` in the left panel, click `assign`, select users and then assign `Azure Active Directory Premium P1` and `Microsoft Azure Multi-Factor Authentication`
      - If the above fails go `Users` and make sure each User has `usage location` set under "Settings" (see image below):
    ![](images/set_user_location.png)

## 1. Deploy VNET and Domain Controllers

### Core SHM configuration properties
The core properties for the Safe Haven Management (SHM) environment must be present in the `dsg_configs/core` folder. These are also used when deploying a DSG environment. 
The following core SHM properties must be defined in a JSON file named `shm_<shm-id>_core_config.json`.

```json
{
    "subscriptionName": "Name of the Azure subscription the management environment is deployed in",
    "domain": "The fully qualified domain name for the management environment",
    "shId": "A short ID to identify the management environment",
    "location": "The Azure location in which the management environment VMs are deployed",
    "ipPrefix": "The three octet IP address prefix for the Class A range used by the management environemnt",
    "dcVmName":  "The VM name of the managment environment Active Directory Domain Controller",
    "dcHostname":  "The hostname of the managment environment Active Directory Domain Controller",
    "dcRgName": "The name of the Resource Group containing the managment environment Active Directory Domain Controller",
    "npsIp": "The IP address of the management environment NPS server",
    "vnetRgName":"The name of the Resource Group containing the Virtual Network for the management environment",
    "vnetName":"The name of the Virtual Network for the management environment",
    "artifactStorageAccount": "The name of the storage account containing installation artifacts for new DSGs within the mangement  environment"
}
```


1. Ensure you are logged into the Azure within PowerShell using the command:
```pwsh
Connect-AzAccount
```
 
2. Set the AzContext to the SHM Azure subscription id:
```pwsh
Set-AzContext -SubscriptionId "<SHM-subscription-id>"
```

3. From a clone of the data-safe-haven repository, deploy the VNET and DCs with the following commands
```pwsh
cd ./data-safe-haven/safe_haven_management_environment/setup
```

Next run `./setup_azure1.ps1` entering the `shId`, defined in the config file, when prompted 

5. Once the script exits successfully you should see the following resource groups under the SHM-subscription:

![](images/resource_groups.png)


## 3. Configure Domain Controllers (DCs)

### Download and install the VPN Client from the virtual network VPN gateway 

1. Navigate to `/safe_haven_management/scripts/local/out/certs/` and double click `client.pfx` to install it (on Mac). Enter the `password`. 
2. Next, on the portal navigate to the Safe Haven Management (SHM) VNet gateway in the SHM subscription via `Resource Groups -> RG_SHM_VNET -> SHM_VNET1_GW`.
3.  Once there open the "Point-to-site configuration page under the "Settings" section in the left hand sidebar.
4. Click the "Download VPN client" link at the top of the page to get the root certificate (VpnServerRoot.cer) and VPN configuration file (VpnSettings.xml).

5. Follow the [VPN set up instructions](https://docs.microsoft.com/en-us/azure/vpn-gateway/point-to-site-vpn-client-configuration-azure-cert) using the Windows or Mac sections as appropriate.

You should now be able to connect to the virtual network. Each time you need to access the virtual network ensure you are connected to it.

### Access the first Domain Controller (DC1) via Remote Desktop

1. Open Microsoft Remote Desktop

2. Click `Add Desktop`

3. Navigate to the `RG_SHM_DC` resource group and then to the `SHMDC1` virtual machine (VM). 

4. Copy the Private IP address and enter it in the `PC name` field on remote desktop. Click Add.

5. Double click on the desktop that appears under `saved desktops`. Enter the username and password:
    - Username: atiadmin
    - Password: 

  - To obtain the password on Azure navigate to the `RG_SHM_SECRETS` resource group and then the `shmvault` key vault. On the left panel select `secrets` and click on `dc_pass`. You can then copy the secret to the clipboard and paste it into Microsoft Remote Desktop. 

### Configure Active Directory on SHMDC1

Once you have accessed SHMDC1 via the Remote Desktop we can configure the DC1. 

1. On the Azure portal navigate to the `RG_SHM_RESOURCES` resource group and then the `shmfiles` container. Click on `Files` and then the `scripts` fileshare. 

2. Click the connect icon on the top bar and then copy the lower powershell command. 

![](images/drivemap.png)

3. Open a powershell on the SHMDC1 VM. Past the powershell command and run. This will map the `scripts` fileshare to the Z: drive. 


4. In the powershell enter the following commands:

```pwsh
New-Item -Path "c:\" -Name "Scripts" -ItemType "directory"
```
```pwsh
Z:
```
```pwsh
copy dc C:/Scripts -Recurse
```

5. Open windows explorer and navigate to `C:\Scripts\dc`. Unzip `SHM_DC.zip` and then copy the contents of the unzipped file to `C:/Scripts/` 

6. Open `Active_Directory_Configuration.ps1` in a file editor. Then edit the following lines to use the custom domain name and save the file:

    - $domainou = "DC=TURINGSAFEHAVEN,DC=AC,DC=UK"
    - $domain = "TURINGSAFEHAVEN.ac.uk"

6. In the powershell navigate to `C:/Scripts/`. Run:
```pwsh
.\Set_OS_Language.ps1
```
```pwsh
.\Active_Directory_Configuration.ps1 -oubackuppath c:\Scripts\GPOs
```
You will be promted to enter a password for the adsync account. Note this down as you will need it when configuring the NPS Server later. 

### Configure Group Policies

1. Open the `Group Policy Management` app. You can search for it using the windows search bar. 

2. Navigate to the "All Servers - Local Administrators" GPO, right click and then click edit

![](images/group_policy_management.png)

3. Navigate to "Computer Configuration" -> "Windows Settings" -> "Security Settings" -> "Restricted Groups"

![](images/restricted_groups.png)

4. Open "Administrators" group object and delete all entries from "Members of this group".
    - Click "Add" -> Add "SG Safe Haven Server Administrators" and "Domain Admins". Click `apply` then `ok`. Now close "Group Policy Management" MMC

5. Open `Active Directory Users and Computers` app (search in windows search bar)

![](images/delegate_control.png)

6. Right click on "Computers" container. Click "Deletegate Control" -> "Next" -> "Add" -> "SG Data Science LDAP Users".

7. Click next -> "Create a custom task to delegate" -> "This folder, existing objects in this folder...."

8. Click next, then Select "Read", "Write", "Create All Child Objects" -> "Delete All Child Objects" -> "Next" -> "Finish". Close the `Active Directory Users and Computers` app.

9. Close the remote desktop instance

### Configure the second domain controller (SHMDC2)

1. Connect to SHMDC2 using Microsoft Remote desktop, the same procedure as for SHMDC1, but using the private IP address for SHMDC2. The Username and Password is the same.

1. On the Azure portal navigate to the `RG_SHM_RESOURCES` resource group and then the `shmfiles` container. Click on `Files` and then the `scripts` fileshare. 

2. Click the connect icon on the top bar and then copy the lower powershell command. 

3. Open a powershell on the SHMDC2 VM. Past the powershell command and run. This will map the `scripts` fileshare to the Z: drive. 

4. In the powershell enter the following commands:

```pwsh
New-Item -Path "c:\" -Name "Scripts" -ItemType "directory"
```
```pwsh
Z:
```
```pwsh
copy dc C:/Scripts -Recurse
```

5. Open windows explorer and navigate to `C:\Scripts\dc`. Unzip `SHM_DC.zip` and then copy the contents of the unzipped file to `C:/Scripts/` 

6. Open `Active_Directory_Configuration.ps1` in a file editor. Then edit the following lines to use the custom domain name and save the file:

    - $domainou = "DC=TURINGSAFEHAVEN,DC=AC,DC=UK"
    - $domain = "TURINGSAFEHAVEN.ac.uk"

6. In the powershell navigate to `C:/Scripts/`. Run:
```pwsh
.\Set_OS_Language.ps1
```

The Domain Controller configuration is now complete. Exit remote destop

## 4. Deploy Network Policy Server (NPS)

1. In the data-safe-haven repository, deploy the NPS server using the following commands:
 ```pwsh
 cd ./data-safe-haven/safe_haven_management_environment/setup
 ```
```
./setup_azure2.ps1 -SubscriptionId "<SHM-subscription-id>"
```

2. When prompted enter the following:

    - Administrator password: In the keyvault under `dcpass` (must be the same password and username as the DCs)
    - Virtual Network Resource Group: RG_SHM_VNET (the name of the resource group)
    - Domain name: The custom domain name

The NPS server will now deploy. This may take some time. 



### Configure the Network Policy Server

1. Connect to NPS Server using Microsoft Remote desktop, the same procedure as for SHMDC1/SHMDC2, but using the private IP address for SHMNPS VM, which is found in the `RG_SHM_NPS` resource group. The Username and Password is the same as for SHMDC1 and SHMDC2.

2. On the Azure portal navigate to the `RG_SHM_RESOURCES` resource group and then the `shmfiles` container. Click on `Files` and then the `scripts` fileshare. 

2. Click the connect icon on the top bar and then copy the lower powershell command. 

3. Open a powershell on the `SHMNPS` VM. Past the powershell command and run. This will map the `scripts` fileshare to the Z: drive. 

4. In the powershell enter the following commands:

```pwsh
New-Item -Path "c:\" -Name "Scripts" -ItemType "directory"
```
```pwsh
Z:
```
```pwsh
copy nps C:/Scripts -Recurse
```

5. Open windows explorer and navigate to `C:\Scripts\dc`. Unzip `SHM_NPS.zip` and then copy the contents of the unzipped file to `C:/Scripts/` 

6. From the PowerShell command window change to `C:\Scripts` and run:
```
.\Prepare_NPS_Server.ps1
```

7. Open the file `C:/Scripts/ConfigurationFile.ini` in an editor. 

8. Find the line `SQLSYSADMINACCOUNTS="TURINGSAFEHAVEN\atiadmin"` and change the domain name to the correct custom domain. Save and exit. 


### SQL Server installation

1. Go back to the Azure portal and navigate to the `RG_SHM_RESOURCES` resource group and then the `shmfiles` container. Click on `Files` and then the `sqlserver` fileshare. 

2. Click the connect icon on the top bar. **Change the driver letter to Y**. Then copy the lower powershell command. 

3. Open a powershell on the `SHMNPS` VM. Past the powershell command and run. This will map the `sqlserver` fileshare to the Y: drive. 

4. Close the powershell. 

5. In Windows explorer navigate to the Y: driver (sqlserver). Double click on `SQLServer2017-SSEI-Expr` and click `run` when prompted. Then chose `Download Media` and select `Express Advanced`. Then click download. 

6. Once downloaded run the downloaded installer. This will extract a folder called `SQLEXPRADV_x64_ENU`

7. Open a command prompt with administrator privileges (right click on command window and click `run as administrator`). Navigate to the `SQLEXPRADV_x64_ENU` folder. 

8. Enter the following commands which will install the SQL Server:

```pwsh
setup /configurationfile=c:\Scripts\ConfigurationFile.ini /IAcceptSQLServerLicenseTerms
```

9. In Windows explorer navigate to the Y: driver (sqlserver). Run the SSMS-Setup-ENU (SQL Management Studio installation) and install with the default settings. When prompted restart the VM. You will need to log back in with Windows Remote Desktop. 

10. Open a new command prompt and navigate to `C:\scripts`. Then enter the following command:

```pwsh
sqlcmd -i c:\Scripts\Create_Database.sql
```
11. Exit the command promt

### NPS Configuration

1. On the NPS VM open the "Network Policy Server" desktop app

2. Click on "Accounting"
3. Select "Configure Accounting"
4. Click "Next" -> "Log to a SQL Server Database" -> "Next" -> "Configure"
5. Enter "SHMNPS" in the "Select or enter server name" box
6. Select "User Windows NT Intergrated Security"
7. Select "NPSAccounting" database from "Select the database on the server" drop down
8. Click "OK"
9. Click "Next" -> "Next" -> "Rebuild" -> "Close"
10. Close the "Network Policy Server" app


### Install Azure Active Directory Connect

1. Download the latest version of the AAD Connect tool from [here](https://www.microsoft.com/en-us/download/details.aspx?id=47594)
    - You will need to temporarily [enable downloads on the VM](https://www.thewindowsclub.com/disable-file-download-option-internet-explorer 
    - You will be promted to add webpages to exceptions. Do this. 

2. Run the installer
    - Agree the license terms -> "Continue"
    - Select "Customize"
    - Click "Install"
    - Select "Password Hash Synchronization" -> "Next"
    - Provide a global administrator details for the Azure Active Directory you are connected to. 
    - Ensure that correct forest (your custom domain name; e.g TURINGSAFEHAVEN.ac.uk) is selected and click "Add Directory"
    - Select "Use and existing account" -> Enter the details of the "localadsync" user. Domaninusername: <DOMAIN>/localadsync Password: Password entered in SHMDC1 setup -> "OK" -> "Next"
    - Verify that UPN matches -> "Next"
    - Select "Sync Selected domains and OUs"
    - Expand domain and delselect all objects
    - Select "Safe Haven Research Users" -> "Next"
    - Click "Next" on "Uniquely identifying your users"
    - Select "Synchronize all users and devices" -> "Next"
    - Select "Password Writeback" -> "Next"
    - Click "Install"
    - Click "Exit"

### Additional AAD Connect Configuration

1. Open the `Synchronization Rules Editor` from the start menu on the SHMNPS VM. 
2. Change the "Direction" drop down to "Outbound"
3. Select the "Out to AAD - User Join" -> Click "Disable". Click edit.
4. Click "Yes" for the "In the Edit Reserved Rule Confirmation" window
5. Set `precedence` to 1. 
6. Select "Transformations" and locate the rule with its "Target Attribute" set to "usageLocation" 
7. Change the "FlowType" column from "Expression" to "Direct"
8. "Source" column click drop-down and choose "c" attribute
9. Click "Save"
10. You will now see a cloned version of the `Out to AAD - User Join`. Delete the original. Then edit the cloned version. Change `Precedence to 115` and edit the name to `Out to AAD - User Join`. Click save. Enable the new rule. 
11. Click the X to close the Synchronization Rules Editor window

12. In the powershell run:

```pwsh
Start-ADSyncSyncCycle -PolicyType Initial
```

14. To verify this worked open a powershell and enter:
```pwsh
Start-ADSyncSyncCycle -PolicyType Delta
```


### MFA Configuation

- Download the "NPS Extension" from Microsoft [here](https://aka.ms/npsmfa)
- Run the installer
- Agree the license terms and click "Install"
- Click "Close" once the install has completed
- Open a PowerShell command windows with administrator privilages
- Chnage to "C:\Program Files\Microsoft\AzureMfa\Config"
- Run:
```pwsh
.\AzureMfaNpsExtnConfigSetup.ps1
```
- Enter "Y" when prompted
- Enter "A" when prompted
- Sign in with the global admin account for your active directory
- Enter your Azure Active directory ID (Note: if you see a service principal error here this is because you don't have any valid P1 licenses, purchase licenses and then re-run the commands in this section)
- Enter "Y" when prompted

#### Installation of Safe Haven Management environment complete.


## 5. Validation 

1. Add a user on the SHMDC1 machine using the `Active Directory Users and Computers` application. 

2. After about 30 minutes the new user should appear on the Azure Active Directory account. Or to force a sync, on the NPS machine open a powershell and call:

```pwsh
Start-ADSyncSyncCycle -PolicyType Delta
```

