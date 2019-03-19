# Safe Haven Management Environment Build Instructions

## Prerequisites

- Completed [checklist](https://github.com/alan-turing-institute/data-safe-haven/blob/214-safe-haven-managment-deployment/safe_haven_management_environment/supplementary/SHM%20Configuration%20Checklist.xlsx) with the exception of the SAS and File share detail for which you'll capture when the storage account is created
- Azure Active Directory with P1 licenses, for MFA with custom domain set as default
- Azure Subscription to build the environment in
- Self signed certificate for Azure Point to Site VPN service [Microsoft Documentation](https://docs.microsoft.com/en-us/azure/vpn-gateway/vpn-gateway-certificates-point-to-site)

## Artifacts Storage Account

- Create an Azure storage account within the subscription that is going to host the SHM VMs
 - Create Blob storage container called "dsc" and copy the files from here to it
 - Create the following Azure "File Shares" and populate as shown below.
   - scripts - copy the files from [here](https://github.com/alan-turing-institute/data-safe-haven/tree/214-safe-haven-managment-deployment/safe_haven_management_environment/scripts) to it
   - sqlserver - download the SQL Express 2017 from [here](https://go.microsoft.com/fwlink/?linkid=853017) and Microsoft SQL Studio from [here](https://docs.microsoft.com/en-us/sql/ssms/download-sql-server-management-studio-ssms?view=sql-server-2017).  The SQL server installation files should be expanded
- Capture the URL and create a SAS token for the blob account and copy into the checklist
- Capture the connection string for SQL and Scripts folders on the Files account and add to the checklist
   
## Virtual Network

- Deploy "shmvnet-template" template
- Complete the following detail:
  - Resource Group: RG_SHM_VNET
  - Location: UK South
  - Virtual Network Name: SHM_VNET1
  - Point to Site VPN certificate CER

- Wait for the deployment to finish before moving on to the Domain Controllers
- Download VPN client from the virtual network VPN gatway and install on your PC

## Domain Controllers

- Ensure that the virutal network has deployed successfully
- Deploy "shmdc-template" template
- Complete the following detail:
  - Resource Group: RG_SHM_DC
  - Location: UK South
  - VM Size
  - Administrator User: atiadmin
  - Administrator Password
  - Safe Mode Password
  - Virtual Network: SHM_VNET1
  - Virtual Network Resource Group: RG_SHM_VNET
  - Artifacts Location: URL to blob
  - Artifacts Location SAS Token: Blob SAS token
  - Domain name: TURINGSAFEHAVEN.AC.UK

### Domain Controller SHMDC1

- Using the P2S VPN connect to SHMDC1 (remote desktop)
- Create a directory called "Scripts" in the root of C:\
- Open a PowerShell command window and paste the storage account "Files" connection string for the "Scripts" share.  This will map a drive to Windows File Explorer
- Copy "SHM_DC.ZIP" file from the file share to C:\Scripts and unzip the contents into this root of this folder
- From the PowerShell command window change to C:\Scripts
- Run:
```
Set_OS_Language.ps1
```
- Run:
```
Active_Directory_Configuration.ps1 -oubackuppath c:\scripts\GPOs
```
- Open the "Group Policy Management" MMC and locate the "All Servers - Local Administrators" GPO and edit it
- Navigate "Computer Configuration" -> "Windows Settings" -> "Security Settings" -> "Restricted Groups"
- Open "Administrators" group object and delete all entries from "Members of this group"
- Click "Add" -> Add "SG Safe Haven Server Administrators" and "Domain Admins"
- Click "OK" to close dialogue window, close "Group Policy Management" MMC
- Open "Active Directory Users and Computers" MMC
- Right click on "Computers" container
- Click "Deletegate Control" -> "Next" -> "Add" -> "SG Data Science LDAP Users" -> "Create a custom task to delegate" -> "This folder, existing objects in this folder...."
- Select "Read", "Write", "Create All Child Objects" -> "Delete All Child Objects" -> "Next" -> "Finish"

### Domain Controller SHMDC2

- Connect to server SHMDC2
- Create a directory called "Scripts" in the root of C:\
- Open a PowerShell command window and paste the storage account "Files" connection string for the "Scripts" share.  This will map a drive to Windows File Explorer
- Copy "SHM_DC.ZIP" file from the file share to C:\Scripts and unzip the contents into this root of this folder
- From the PowerShell command window change to C:\Scripts
- Run:
```
Set_OS_Language.ps1
```
- Domain controller configuration complete, move onto to deploying the NPS server

## Network Policy Server

- Ensure that all the configuration on the domain controllers has been completed before deploying the NPS server
- Deploy "shmnps-template" template
- Complete the following detail:
  - Resource Group: RG_SHM_NPS
  - Location: UK South
  - VM Size
  - Administrator User: atiadmin
  - Administrator Password
  - Virtual Network: SHM_VNET1
  - Virtual Network Resource Group: RG_SHM_VNET
  - Domain name: TURINGSAFEHAVEN.AC.UK

- Using the P2S VPN connect to SHMNPS (remote desktop)
- Create a directory called "Scripts" in the root of C:\
- Open a PowerShell command window and paste the storage account "Files" connection string for the "scripts" share.  This will map a drive to Windows File Explorer
- Copy "SHM_NPS.ZIP" file from the file share to C:\Scripts and unzip the contents into this root of this folder
- From the PowerShell command window change to C:\Scripts
- Run:
```
Prepare_NPS_Server.ps1
```

### SQL Server installation
- Obtain the connection string for the "sqlserver" file share and run this in the PowerShell command windows to map a drive to the SQL server installation software. Note: change the drive letter on the connection script so not to conflict with the scripts share.
- Close the PowerShell command window
- Open a command prompt with administrator privilages
- Change to the drive letter you mapped in the connection command above and navigate to the directory where the SQL installation files are located i.e. Y:\SQLEXPR_x64_ENU
- Enter the following command:
```
setup /configurationfile=c:\Scripts\ConfigurationFile.ini /IAcceptSQLServerLicenseTerms
```
- SQL Server will now perform a silent installation, it will return to the command prompt when complete
- Run the SQL Management Studio installation from the sqlserver share, install with the default settings
- Exit the command prompt
- Open a new command prompt
- Change to C:\scripts
- Enter the following command:
```
sqlcmd -i c:\Scripts\Create_Database.sql
```
- Exit the command prompt

### NPS Configuration

- Open the "Network Policy Server" MMC
- Click on "Accounting"
- Select "Configure Accounting"
- Click "Next" -> "Log to a SQL Server Database" -> "Next" -> "Configure"
- Enter "SHMNPS" in the "Select or enter server name" box
- Select "User Windows NT Intergrated Security"
- Select "NPSAccounting" database from "Select the database on the server" drop down
- Click "OK"
- Click "Next" -> "Next" -> "Rebuild" -> "Close"
- Close the "Network Policy Server" MMC

### Install Azure Active Directory Connect

- Download the latest version of the AAD Connect tool from [here](https://www.microsoft.com/en-us/download/details.aspx?id=47594)
- Run the installer
- Agree the license terms -> "Continue"
- Select "Customize"
- Click "Install"
- Select "Password Hash Synchronization" -> "Next"
- Provide a global administrator for the Azure Active Directory you are connection to
- Ensure that correct forest is selected and click "Add Directory"
- Select "Use and existing account" -> Enter the details of the "localadsync" user -> "OK" -> "Next"
- Verify that UPN matches -> "Next"
- Select "Sync Selected domains and OUs"
- Expand domain and delselect all objects
- Select "Safe Haven Research Users" -> "Next"
- Click "Next" on "Uniquely identifying your users"
- Select "Synchronize all users and devices" -> "Next"
- Select "Password Writeback" -> "Next"
- Click "Install"
- Click "Exit"

#### Additional AAD Connect Configuration

- Open the "Synchronization Rules Editor" from the "Start menu"
- Change the "Direction" drop down to "Outbound"
- Select the "Out to AAD - User Join" -> Click "Edit"
- Click "No" for the "In the Edit Reserved Rule Confirmation" window
- Select "Transformations" and locate the rule with its "Target Attribute" set to "usageLocation" 
- Change the "FlowType" column from "Expression" to "Direct"
- "Source" column click drop-down and choose "c" attribute
- Cick "Save"
- Click the X to close the Synchronization Rules Editor window

## MFA Configuation

- Download the "NPS Extension" from Microsoft [here](https://aka.ms/npsmfa)
- Run the installer
- Agree the license terms and click "Install"
- Click "Close" once the install has completed
- Open a PowerShell command windows with administrator privilages
- Chnage to "C:\Program Files\Microsoft\AzureMfa\Config"
- Run:
```
.\AzureMfaNpsExtnConfigSetup.ps1
```
- Enter "Y" when prompted
- Enter "A" when prompted
- Sign in with the global admin account for your active directory
- Enter your Azure Active directory ID (Note: if you see a service principal error here this is because you don't have any valid P1 licenses, purchase licenses and then re-run the commands in this section)
- Enter "Y" when prompted

## Installation of Safe Haven Management environment complete.