# DSH Security checklist

PR : https://github.com/alan-turing-institute/data-safe-haven/compare/checklist?expand=1 

![](https://i.imgur.com/oYluwet.png)


In this check list we aim to do the following things.

- Establish our current claims about the Data Safe Haven
- Establish what these security claims mean in terms of implementation
- How we can verify that we actually do what we say

In particular for verification we will focus on user security and permissions. We will establish two types of verification Black Box (BB) and White Box (WB). BB verification involves testing with a user account to confirm levels of user access. In contrast, WB verification involves using an admin account to check the specific configuration required to set user access permissions.

# 1 Multifactor Authentication and Password strength

### We claim:

Users are required to authenticate with Multi Factor Authentication (MFA) in order to access the secure analysis environment.

Passwords are strong

### Which means:

Users must set up MFA before accessing the secure analysis environment. Users cannot access the environment without MFA. Users are strongly advised to create passwords of a certain strength.


### Verify by (BB):


- Create a new user without MFA and check that the user cannot access the environment regardless of other credentials.
    - a) Follow the [SRE deployment guide](https://github.com/alan-turing-institute/data-safe-haven/blob/master/docs/deploy_sre_instructions.md#bicyclist-set-up-a-non-privileged-user-account) for setting up a non privileged user account
    - b) Attempt to sign in to the remote desktop web client using the user account.
    - c) **Verify:** access fails
- Check that the user is able to successfully set up MFA with the right credentials
    - a) Visit https://aka.ms/mfasetup
    - b) Attempt to login and reset password
    - c) **Verify:** user guided to set up MFA
    - d) Set up MFA
    - e) **Verify:** successfully set up MFA
    
- Check that the user is able to successfully login to the environment once MFA is set up and using the right credentials
    - a) **Verify**: login to the portal using the user account and check that MFA is requested
    - b) **Verify**: login into the remote desktop web client successfully and check that MFA is requested

<!---
 - New passwords are enforced to be above a certain number of characters in length
    - MOR: We haven't figured out how to enforce custom password requirements. I believe the default 
    - KX: I remember when creating a new account on the SHM DC, I had to create a password with minimum length. I believe though that we then ask users to reset this password when enabling MFA, which I'm not sure has any requirements
--->

### Verify by (WB):


- Users are required to set up MFA before they can access the environment
    - 1) Using an AAD admin account, go to `AAD -> Users -> Multi-Factor authentication -> Service settings`
    - 2) **Verify**: app passwords are unenabled (this stops any users bypassing MFA)
    - 3) **Verify**: No trusted ips (this means that no one can skip MFA)
    - 4) **Verify**: Option to remember trusted devices is unchecked (this means the user must authenticate each time)

- Users require a license before they can access the environment
    - 1) Create a user account, add a license and then set up MFA
    - 2) To add a license, login using an AAD admin account, go to `AAD -> Users -> <select user> -> Licenses -> Assignments`
         and add a P1 license
    - 3) Login to the web client using the user account
    - 4) Remove the license from the user account
    - 5) **Verify**: unable to login to the web client anymore.


# 2 Isolated Network 

### We claim:

The DSH Virtual Network is isolated from external connections (both tier 2 and 3)

### Which means:

Users cannot access any part of the network without already being in the network. Being part of the network involves connecting using an SHM specific Management VPN.

Whilst in the network, one cannot use the internet to connect outside the network.

SREs in the same SHM are still isolated from one another.

### Verify by:

- Connect to the SHM DC, NPS, Data server if and only if connected to the SHM VPN:
    - a) Connect to the SHM VPN
    - b) Connect to the SHM DC. IP details in RG_SHM_DC, login details in SHM secrets as domain admin
    - c) Connect to the SHM NPS. IP details in RG_SHM_NPS, same login
    - d) **Verify:** Connection works
    - e) Disconnect from the SHM VPN
    - f) Attempt to connect to the SHM DC and NPS again
    - g) **Verify:** Connection fails
- Be unable to connect to the internet from within a DSVM on the SRE network.
    - a) Login as a user to a DSVM from within the SRE by using the web client.
    - b) Choose your favourite three websites and attempt to access the internet using a browser
    - c) **Verify**: Connection fails
    - d) Alternative if using terminal **Verify**: type `curl <website>` and check that you get the following response `<insert firewall message denying the connection as it matched the default rule>`
- Check that users cannot connect beween two SREs within the same SHM, even if they have access to both SREs
    - a) Ensure you have two SREs managed by the same SHM
    - b) Connect to a DSVM in SRE A as a user by using the web client.
    - c) Attempt to connect to a DSVM SRE B via remote desktop or SSH
    - d) **Verify:** Connection fails
    - e) Repeat the test, this time trying to connect from a DSVM in SRE B to a DSVM in SRE A
- Check that one can connect between the SHM->SRE and SRE->SHM
    - a) Connect to the SHM DC (using the SHM VPN) as domain admin
    - b) Connect to an SRE DSVM using remote desktop or SSH
    - c) **Verify:** Connection succeeds
    - d) Disconnect from both
    - e) Connect to the SRE DSVM
    - f) Connect to the SHM DC using remote desktop or SSH
    - g **Verify:** Connection suceeds [MOR: Ideally it should not be possible to log into any SHM VMs from any SRE VMs, even with admin credentials due to network rules forbidding the connection]

### Verify by (WB):

- Check that the network rules are set appropriately to block outgoing traffic
    - a) Check `RG_SRE_NETWORKING -> NSG_SRE_SANDBOX_COMPUTE`
    - b) **Verify:** There exists an OutboundDenyInternet rule with Destination `Internet` and Action `Deny` and no higher priority rule allows connection to the internet.



# 3 User devices

### We claim: 

At tier 3, only managed devices can connect to the DSH environment.

At tier 2, all kinds of devices can connect to the DSH environment (with VPN connection and correct credentials).

### This means

A managed device is a device provided by a partner institution in which the user does not have admin or root access.

Network rules for the higher tier Environments can permit access only from Restricted network IP ranges that only permit managed devices to connect.

### Verify by:


For tier 2: 

- One can connect regardless of device as long as one has the correct VPN and credentials
    - a) Using a personal device, connect to the environment using the correct VPN and credentials
    - b) **Verify**: Connection suceeds
    - c) Using a managed device, connect to the environment using the correct VPN and credentials.
    - d) **Verify**: Connection suceeds
- There are are network rules permitting access only from the Turing Tier 2 and Tier 3 VPNs
    - a) Check network rules
    - b) **Verify**: The `RDS` NSG has network rules allowing **inbound** access from `<insert Turing Tier 2 and Tier 3 IP addresses here>` 
    - c) **Verify:** All other NSGs have an inbound Deny All rule and no higher priority rule allowing inbound connections from outside the Virtual Network.


For tier 3:

- A device is managed by checking user permissions and where the device has come from. We should check that it is managed by the partner institution's IT team.
    - a) Check that the device is managed by the partner institution IT team
    - b) **Verify**: The user lacks root access
- A device is able to connect to the environment if and only if it is managed (with correct VPN and credentials)
    - a) Using a personal device, attempt to connect to the environment using the correct VPN and credentials
    - b) **Verify**: Connection fails
    - c) Using a managed device, attempt to connect to the environment using the correct VPN and credentials
    - d) **Verify**: Connection suceeds
- We can check that a managed device is within a specific IP range and that the environment firewall accepts it.
- We can check that the firewall blocks any device with an IP outside of the specified range




# 4 Physical security

### We claim:

At tier 3 access is limited to certain research office spaces

### Which means:

Medium security research spaces control the possibility of unauthorised viewing. Card access or other means of restricting entry to only known researchers (such as the signing in of guests on a known list) is required. Screen adaptations or desk partitions can be adopted in open-plan spaces if there is a high risk of "visual eavesdropping".

Firewall rules for the Environments can permit access only from Restricted network IP ranges corresponding to these research spaces.

### Verify by:

For tier 3:

- Connection outside of the research office space is not possible. 
    - a) Attempt to connect from home using a managed device and the correct VPN connection and credentials
    - b) **Verify:** connection fails
- Connection from within the research office space is possible.
    - a) Attempt to connect from research office using a managed device and the correct VPN connection and credentials
    - b) **Verify:** connection suceeds
- Check the network IP ranges corresponding to the research spaces and compare against the IPs accepted by the firewall.
- Physically confirm that measures such as screen adapations or desk partitions are present.
    - Non technical implementation

# 5 Remote connections

### We claim:

Connections can only be made via remote desktop (Tier 2+)

### This means

User can connect via remote desktop but cannot connect through other means such as SSH (without access to the VPN)

### Verify by:

- Connect as a user to the DSVM via the remote desktop web client 
    - a) login as a user via the remote desktop web client (without using VPN)
    - b) **Verify:** login succeeds
- Unable to connect as a user to the DSVM via SSH
    - a) Download Putty and attempt to SSH to a DSVM (without using VPN)
    - b) **Verify:** login fails 
    - c) **Verify:** The RDS server and Firewall are the **only** resources with public IP addresses


# 6 Copy-paste

### We claim:

Copy and paste is disabled on the remote desktop


### Which means:

One cannot copy something from outside the network and paste it into the network. One cannot copy something from within the network and paste it outside the network.


### Verify by:

- One is unable to copy some text from outside the network, into a DSVM and vice versa
    - a) Copy some text from your deployment device
    - b) Login to a DSVM via the remote desktop web client
    - c) Open up a notepad or terminal on the DSVM and attempt to paste the text to it.
    - d) **Verify:** paste fails
    - e) Write some next in the note pad or terminal of the DSVM and copy it
    - f) Attempt to copy the text externally to deployment device (e.g. into URL of browser)
    - g) **Verify:** paste fails
- One can copy between VMs inside the network
    - a) Login to a DSVM via the remote desktop web client
    - b) Open up a notepad or terminal on the DSVM and attempt to paste the text to it.
    - c) Connect to another DSVM via the remote desktop web client (as a second tab)
    - d) Attempt to paste the text to it.
    - e) **Verify:** paste succeeds

### Verify by:

- Security group policy that blocks clip board access


# 7 Data ingress

### We claim:

All data transfer to the Turing should be via our secure data transfer process, which provides the Dataset Provider time-limited, write-only access to a dedicated data ingress volume from a specific location.

Ingressed data is stored in a holding zone until approved to be added for user access.

### This means

Prior to access to the ingress volume being provided, the Dataset Provider Representative must provide the IP address(es) from which data will be uploaded and an email address to which a secure upload token can be sent. Once these details have been received, the Turing will open the data ingress volume for upload of data.

To minimise the risk of unauthorised access to the dataset while the ingress volume is open for uploads, the following security measures are in place:

- Access to the ingress volume is restricted to a limited range of IP addresses associated with the Dataset Provider and the Turing.
- The Dataset Provider receives a write-only upload token. This allows them to upload, verify and modify the uploaded data, but does not viewing or download of the data. This provides protection against an unauthorised party accessing the data, even they gain access to the upload token.
- The upload token expires after a time-limited upload window.
- The upload token is transferred to the Dataset Provider via a secure email system.


### Verify by:

First identify a select list of IP addresses and an email for which the data will be uploaded and a secure upload token sent. Open the data ingress volume.

- Ensure that the secure upload token is sent only to the email address provided and via a secure email system
   - a) **Verify:** that email system is secure
   - b) **Verify:** that a secure upload token can be created with write-only permissions

- Ensure that data ingress works for connections from within the accepted IP address and does not work for connections outside the IP address, even if the correct upload token is present.
    - a) Identify a test device that will have a whitelisted IP address
    - b) Generate a secure upload token with write-only permissions with limited time period
    - c) Attempt to write to the ingress volume via the test device
    - d) **Verify:** that writing suceeds
    - e) **Verify:** that one is unable to view or download from ingress
    - f) Switch to a device that lacks a whitelisted IP address
    - g) Attempt to write to the ingress volume via the test device
    - h) **Verify:** that the access token fails.

- Check the token duration and ensure that the upload fails if the duration has expired. 
    - a) Create a write-only token with short duration
    - b) **Verify:** you can connect and write with the token during the duration
    - c) **Verify:** you cannot connect and write with the token after the duration has expired

- Check that the overall ingress works by uploading different kinds of files, e.g. data, images, scripts (if appropriate).


# 8 Storage volumes and egress
### We claim: 
The analysis environment contains a number of different storage volumes. Some of these storage volumes include write permissions that can then be viewed by administrators.

Egressed data is held in a holding zone until approved to egressed out of the environment.

### This means:

A Secure Data volume is a read-only volume that contains the secure data for use in analyses. It is mounted as read-only in the analysis Environments that must access it. One or more such volumes will be mounted depending on how many managed secure datasets the Environment has access to.

A Secure Document volume contains electronically signed copies of agreements between the Data Provider and the Turing.

A Secure Scratch volume is a read-write volume used for data analysis. Its contents are automatically and regularly deleted. Users can clean and transform the sensitive data with their analysis scripts, and store the transformed data here.

An Output volume is a read-write area intended for the extraction of results, such as figures for publication.

The Software volume is a read-only area which contains software used for analysis.

A Home volume is a smaller read-write volume used for local programming and configuration files. It should not be used for data analysis outputs, though this is enforced only in policy, not technically. Configuration files for software in the software volume point to the Home volume.

A domain administrator can view these volumes by logging into the Data Server. 

### Verify by:


- Confirm that a user is able to read the different storage volumes and write to Output and Home
    - a) Login to a DSVM as a non privileged user account via the remote desktop web client
    - b) Open up a file explorer and search for the various storage volumes
    - c) **Verify:** that the different storage volumes exist and can be read (opened)
    - d) **Verify:** that one can write (move files to) Output and Home
    - e) **Verify:** that one cannot write (move files to) the other storage volumes or to outside the environment
- Confirming that the different volumes exist on the Data Server and that logging on requires domain admin permissions
    - a) Login as domain admin to the SRE Data Server. IP address can be found `RG_SRE_DATA` -> `DAT-SRE-<sreID>`
    - b) Go to `This PC`
    - c) **Verify:** the volumes exist
    - d) **Verify:** that a user has written a file to the Output storage volume
    - e) **Verify:** that a written file can be taken out of the environment

# 9 Software Ingress
### We claim:

The base data science virtual machine provided in the secure analysis Environments comes with a wide range of common data science software pre-installed, as well as package mirrors. For other kinds of software this must be ingressed seperately.

Ingressed software is stored in a holding zone until approved to be added for user access.

### Which means:

For lower tier environments, outbound internet access means users can directly ingress their software from the internet. For higher tier environments we use alternative means.

- Installation during deployment
    - If known in advance, software can be installed during DSVM deployment whilst there is still internet access, but before project data is added. Once the software is installed, the DSVM is ingressed into the environment with a one way lock.
- Installation after deployment
    - Once a DSVM has been deployed into the analysis environment it cannot be moved out. There is no outbound internet access.
    - Software is ingressed in a similar manner to data. Researchers are provided temporary write-only access to the software ingress volume (external mode). The access is then revoked and the software is then reviewed. If it passes review, the software ingress volume is changed to provide researchers with read-only access to the environment (internal mode).
    - If the software requires administrator rights to install, a System Manager must do this. Otherwise, the researcher can do this themselves.

### Verify by:

During deployment:
- Check that one can install software during deployment by using outbound internet
- Check that outbound internet is closed before adding any project data

After deployment:
- Check that outbound internet access on the DSVM is closed off with the following tests:
    - Check the network rules block
    - Attempt to access some of your favourite websites (and fail)
    - Attempt to download some software via terminal (and fail)
- Check that the software ingress volume works correctly:
    - Check that the volume can be changed to external mode and that the researcher can write (but not read) the volume
    - Check that we can revoke write access successfully
    - Check that we can view software that has been written to the volume and that only administrators can read the volume
    - Check that the volume can be changed to internal mode so that other researchers can read it (but not write)
    - Check that software that requires administraor rights to install, can only be run by a System manager.

# 10 Package mirrors


### We claim:

Tier 2: User can access full package mirrors

Tier 3: User can only access whitelisted package mirrors

### This means:

Tier 2: The user can access any package included within our mirrors. They can freely use these packages without restriction.

Tier 3: The user can only access a specific set of packages that we have agreed with. They will be unable to download any package not on the whitelist.


### Verify by:


Tier 2: 

- Download packages from the full mirror.
    - a) Login as a user into a DSVM via remote desktop web client
    - b) Open up a terminal
    - c) Attempt to install any package that is not included at base

Tier 3:
- Download packages on the whitelist
    - a) Login as a user into a DSVM via remote desktop web client
    - b) Check that the package is not installed on the VM `sudo apt list <package>` but on the whitelist
    - c) Attempt to download the package 
    - d) **Verify:** the download suceeds
    - e) Take a package that is not included in the whitelist
    - f) Attempt to download the package
    - g) **Verify:** the download fails

# 11 Azure Firewalls

### We claim:

An Azure Firewall ensures that the administrator VMs have the minimal level of internet access required to function.

### Which means:

Whilst all user access VMs are entirely blocked off from the internet, this is not the case for administrator access VMs such as the SHM-DC, SRE DATA server. An Azure Firewall governs the internet access provided to these VMs, limiting them mostly to downloading Windows updates.


### Verify by:

- Admin has limited access to the internet
    - a) Connect to an administrator VM such as the SHM-DC
    - b) Attempt to connect to your favourite non standard site
    - c) **Verify:** connection fails 
- Admin can download Windows updates
    - a) Connect to an administrator VM such as the SHM-DC
    - b) Attempt to download a Windows update
    - c) **Verify:** download and update successful

# Non technical security implementation

## User addition sign-off

Non technical implementation

## Data classification sign-off

Non technical implementation

## Software ingress sign-off

Non technical implementation
