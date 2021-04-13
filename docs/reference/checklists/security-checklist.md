# Security evaluation checklist

In this check list we aim to do the following things.

+ Establish our current claims about the Data Safe Haven
+ Establish what these security claims mean in terms of implementation
+ How we can verify that we actually do what we say

In particular for verification we will focus on user security and permissions. We will establish two types of verification **Black Box (BB)** and **White Box (WB)**. BB verification involves testing with a user account to confirm levels of user access. In contrast, WB verification involves using an admin account to check the specific configuration required to set user access permissions.

An overview of our security controls is shown here

<p align="center">
    <img src="../../images/security_checklist/recommended-controls.png" width="80%" title="recommended-controls">
</p>

## How to check the list off for a release

1. Deploy SHM and both a tier 2 and 3 SRE from your release code
2. Create an issue called `Carry out security evaluation checklist for release x.x.x`
3. Using [#977](https://github.com/alan-turing-institute/data-safe-haven/issues/977) as a guide, create the checklist as per this document and check it off as
    - The :camera: indicates that you should **Verify** by adding a screenshot(s) of your evidence to the issue comments, which you can use the numbering to reference
    - The :white_check_mark: means that you should **Verify** by ticking a box to say you've done this, but that a screenshot is not needed

## Contents

+ [Prerequisites](#prerequisites)
+ [1. Multifactor Authentication and Password strength](#1-multifactor-authentication-and-password-strength)
+ [2. Isolated Network](#2-isolated-network)
+ [3. User devices](#3-user-devices)
+ [4. Physical security](#4-physical-security)
+ [5. Remote connections](#5-remote-connections)
+ [6. Copy-and-paste](#6-copy-and-paste)
+ [7. Data ingress](#7-data-ingress)
+ [8. Storage volumes and egress](#8-storage-volumes-and-egress)
+ [9. Software Ingress](#9-software-ingress)
+ [10. Package mirrors](#10-package-mirrors)
+ [11. Azure Firewalls](#11-azure-firewalls)
+ [12. Non technical security implementation](#12.-non-technical-security-implementation)

## Prerequisites

If you haven't already, you'll need download a VPN certificate and configure [VPN access](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#download-a-client-vpn-certificate-for-the-safe-haven-management-network) for the SHM that the SRE you're testing uses and make sure you can log in to the [domain controller (DC1) via Remote Desktop](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#configure-the-first-domain-controller-dc1-via-remote-desktop), as well as the [network policy server (NPS)](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#log-in-to-the-nps-vm-using-microsoft-remote-desktop).

## 1. Multifactor Authentication and Password strength

### We claim:

Users are required to authenticate with Multi Factor Authentication (MFA) in order to access the secure analysis environment.

Passwords are strong

### Which means:

Users must set up MFA before accessing the secure analysis environment. Users cannot access the environment without MFA. Users are strongly advised to create passwords of a certain strength.

### Verify by (BB):

1. Create a new user without MFA and check that the user cannot access the apps
 + a) Following the [SRE deployment guide](../../tutorial/deployment_tutorials/how-to-deploy-sre.md#bicyclist-optional-set-up-a-non-privileged-user-account) for setting up a non privileged user account, create an account, then check the following before (d) and after (e) adding them to the `SG <SRE ID> Research Users` group.
 + b) Visit https://aka.ms/mfasetup in an incognito browser
 + c) Attempt to login and reset password, but **do not complete MFA** (see [these steps](../../how_to_guides/user_guides/user-guide.md#closed_lock_with_key-set-a-password))
 + d) :camera: **Verify before adding to group**: Login to the remote desktop web client (`https://<SRE ID>.<safe haven domain> (eg. https://sandbox.dsgroupdev.co.uk/`) works but apps cannot be viewed
 + e) :camera: **Verify after adding to group**: Login again and check that apps can now be viewed
 + f) :camera: **Verify**: attempt to login to DSVM Main (Desktop) fails
2. Check that the user is able to successfully set up MFA
  + a) Visit https://aka.ms/mfasetup again
  + b) Login as the user you set up
  + c) :white_check_mark: **Verify:** user guided to set up MFA
  + d) Set up MFA as per [the user guide instructions](../../how_to_guides/user_guides/user-guide.md#door-set-up-multi-factor-authentication)
  + e) :camera: **Verify:** successfully set up MFA
3. Check that MFA is working as we expect
  + a) :camera: **Verify**: login to the portal using the user account and check that MFA requested
  + b) Login into the remote desktop web client (`https://<SRE ID>.<safe haven domain> (eg. https://sandbox.dsgroupdev.co.uk/`)
  + c) :white_check_mark: **Verify**: that MFA is requested on first attempt to log in to DSVM Main (Desktop)

### Verify by (WB):

4. Users are required to set up MFA before they can access the environment
  + a) Using an AAD admin account, go to `AAD -> Users -> Multi-Factor authentication -> Service settings`
  + b) :camera: **Verify** all of the following with a single screenshot: i) `app passwords` are set to "Do not allow users to create app passwords to sign in to non-browser apps" (this stops any users bypassing MFA). ii) `trusted ips->Skip multi-factor authentication for requests from federated users on my intranet` is unchecked. iii) Checkbox under `remember multi-factor authentication on trusted device` is unchecked (this means the user must authenticate each time)

## 2. Isolated Network

### We claim:

The DSH Virtual Network is isolated from external connections (both tier 2 and 3)

### Which means:

Users cannot access any part of the network without already being in the network. Being part of the network involves connecting using an SHM specific Management VPN.

Whilst in the network, one cannot use the internet to connect outside the network.

SREs in the same SHM are still isolated from one another.

### Verify by (BB):

1. Connect to the SHM DC, NPS, Data server if and only if connected to the SHM VPN:
  + a) Connect to the SHM VPN
  + b) Connect to the SHM DC
  + c) Connect to the SHM NPS
  + d) :white_check_mark: **Verify:** Connection works
  + e) Disconnect from the SHM VPN
  + f) Attempt to connect to the SHM DC and NPS again
  + g) :white_check_mark: **Verify:** Connection fails
2. Be unable to connect to the internet from within a DSVM on the SRE network.
  + a) Login as a user to a DSVM from within the SRE by using the web client.
  + b) Choose your favourite three websites and attempt to access the internet using a browser
  + c) :camera: **Verify**: Connection fails
  + d) :camera: **Verify**: type `curl <website>` into terminal and check that you get a response like: `curl: (6) Could not resolve <website>`
3. Check that users cannot connect between two SREs within the same SHM, even if they have access to both SREs
  + a) Ensure you have two SREs managed by the same SHM
  + b) Connect to a DSVM in SRE A as a user by using the web client. On a separate browser window, do the same for SRE B.
  + c) Attempt to copy and paste a file from one SRE desktop to another
  + d) :white_check_mark: **Verify:** Copy and paste is not possible
  + e) Attempt to connect to SRE B's DSVM via SSH from SRE A:
  + f) Click on `DSVM Main (SSH)` from the `All Resources` tab of the web client window you have open for SRE A
  + g) Right click on the PuTTY terminal and click `New Session...`
  + h) Enter the IP address for SRE B (you can find this by clicking `DSVM Main (SSH)` in the SRE B window you have open)
  + i) Click `Open`
  + j) :camera: **Verify:** Connection fails with `Network error: Connection timed out`
4. (**EC: I'm not sure this check makes sense, check later or delete - perhaps we can chack what Martin suggests below instead**) Check that one can connect between the SHM->SRE and SRE->SHM
  + a) Connect to the SHM DC (using the SHM VPN) as domain admin
  + b) Connect to an SRE DSVM using remote desktop or SSH
  + c) :white_check_mark: **Verify:** Connection succeeds
  + d) Disconnect from both
  + e) Connect to the SRE DSVM
  + f) Connect to the SHM DC using remote desktop or SSH
  + g :white_check_mark: **Verify:** Connection succeeds [MOR: Ideally it should not be possible to log into any SHM VMs from any SRE VMs, even with admin credentials due to network rules forbidding the connection]

### Verify by (WB):

5. Check that the network rules are set appropriately to block outgoing traffic
  + a) Visit the portal and find `NSG_SHM_<SHM ID>_SRE_<SRE ID>_COMPUTE`, then click on the `Outbound security rules` under `Settings`
  + b) :camera: **Verify:** There exists an `DenyInternetOutbound` rule with Destination `Internet` and Action `Deny` and no higher priority rule allows connection to the internet.

## 3. User devices

### We claim:

At tier 3, only managed devices can connect to the DSH environment.

At tier 2, all kinds of devices can connect to the DSH environment (with VPN connection and correct credentials).

### This means

A managed device is a device provided by a partner institution in which the user does not have admin or root access.

Network rules for the higher tier Environments can permit access only from Restricted network IP ranges that only permit managed devices to connect.

### Verify by:

For tier 2:

1. One can connect regardless of device as long as one has the correct VPN and credentials
  + a) Using a personal device, connect to the environment using the correct VPN and credentials
  + b) :white_check_mark: **Verify**: Connection succeeds
  + c) Using a managed device, connect to the environment using the correct VPN and credentials.
  + d) :white_check_mark: **Verify**: Connection succeeds
2. There are are network rules permitting access only from the Turing Tier 2 and Tier 3 VPNs
  + a) Navigate to the NSG for this SRE in the portal: `NSG_SHM_<SHM ID>_SRE_<SRE ID>_RDS_SERVER`
  + b) :camera: **Verify**: The `RDS` NSG has network rules allowing **inbound** access from the IP address of the tier 2 SRE
  + c) :white_check_mark: **Verify:** All other NSGs have an inbound Deny All rule and no higher priority rule allowing inbound connections from outside the Virtual Network.

For tier 3:

3. A device is managed by checking user permissions and where the device has come from. We should check that it is managed by the partner institution's IT team.
  + a) Check that the device is managed by the partner institution IT team
  + b) :white_check_mark: **Verify**: The user lacks root access
4. A device is able to connect to the environment if and only if it is managed (with correct VPN and credentials)
  + a) Using a personal device, attempt to connect to the environment using the correct VPN and credentials
  + b) :white_check_mark: **Verify**: Connection fails
  + c) Using a managed device, attempt to connect to the environment using the correct VPN and credentials
  + d) :white_check_mark: **Verify**: Connection succeeds
5. We can check that a managed device is within a specific IP range and that the environment firewall accepts it.
6. We can check that the firewall blocks any device with an IP outside of the specified range.

## 4. Physical security

### We claim:

At tier 3 access is limited to certain research office spaces

### Which means:

Medium security research spaces control the possibility of unauthorised viewing. Card access or other means of restricting entry to only known researchers (such as the signing in of guests on a known list) is required. Screen adaptations or desk partitions can be adopted in open-plan spaces if there is a high risk of "visual eavesdropping".

Firewall rules for the Environments can permit access only from Restricted network IP ranges corresponding to these research spaces.

### Verify by:

For tier 3:

1. Connection outside of the research office space is not possible.
  + a) Attempt to connect to the tier 3 SRE web client from home using a managed device and the correct VPN connection and credentials
  + b) :white_check_mark: **Verify:** connection fails
2. Connection from within the research office space is possible.
  + a) Attempt to connect from research office using a managed device and the correct VPN connection and credentials
  + b) :white_check_mark: **Verify:** connection succeeds
3. Check the network IP ranges corresponding to the research spaces and compare against the IPs accepted by the firewall.
4. :white_check_mark: **Verify:** Physically confirm that measures such as screen adaptions or desk partitions are present.

## 5. Remote connections

### We claim:

Connections can only be made via remote desktop (Tier 2+)

### This means

User can connect via remote desktop but cannot connect through other means such as SSH (without access to the VPN)

### Verify by:

1. Connect as a user to the DSVM via the remote desktop web client
  + a) login as a user via the remote desktop web client (without using VPN)
  + b) :white_check_mark: **Verify:** login succeeds
2. Unable to connect as a user to the DSVM via SSH
  + a) Find the public IP address for the `RDG-SRE-<SRE ID>` VM by searching for this VM in the portal, then looking at `Connect` under `Settings`.
  + b) :camera: **Verify:** ssh login fails: `ssh user.name@<SRE ID>.<Domain>.co.uk@<Public IP>` (e.g. `ssh john.doe@testa.dsgroupdev.co.uk@<Public IP>`)
  + c) :camera: **Verify:** The RDS server and Firewall are the **only** resources with public IP addresses

## 6. Copy-and-paste

### We claim:

Copy and paste is disabled on the remote desktop

### Which means:

One cannot copy something from outside the network and paste it into the network. One cannot copy something from within the network and paste it outside the network.

### Verify by:

1. One is unable to copy some text from outside the network, into a DSVM and vice versa
  + a) Copy some text from your deployment device
  + b) Login to a DSVM via the remote desktop web client
  + c) Open up a notepad or terminal on the DSVM and attempt to paste the text to it.
  + d) :camera: **Verify:** paste fails
  + e) Write some next in the note pad or terminal of the DSVM and copy it
  + f) Attempt to copy the text externally to deployment device (e.g. into URL of browser)
  + g) :camera: **Verify:** paste fails
2. One can copy between VMs inside the network
  + a) Login to a DSVM via the remote desktop web client
  + b) Open up a notepad or terminal on the DSVM and attempt to paste the text to it.
  + c) Connect to another DSVM via the remote desktop web client (as a second tab)
  + d) Attempt to paste the text to it.
  + e) :camera: **Verify:** paste succeeds

### Verify by:

+ Security group policy that blocks clip board access

## 7. Data ingress

### We claim:

All data transfer to the Turing should be via our secure data transfer process, which provides the Dataset Provider time-limited, write-only access to a dedicated data ingress volume from a specific location.

Ingressed data is stored in a holding zone until approved to be added for user access.

### This means

Prior to access to the ingress volume being provided, the Dataset Provider Representative must provide the IP address(es) from which data will be uploaded and an email address to which a secure upload token can be sent. Once these details have been received, the Turing will open the data ingress volume for upload of data.

To minimise the risk of unauthorised access to the dataset while the ingress volume is open for uploads, the following security measures are in place:

+ Access to the ingress volume is restricted to a limited range of IP addresses associated with the Dataset Provider and the Turing.
+ The Dataset Provider receives a write-only upload token. This allows them to upload, verify and modify the uploaded data, but does not viewing or download of the data. This provides protection against an unauthorised party accessing the data, even they gain access to the upload token.
+ The upload token expires after a time-limited upload window.
+ The upload token is transferred to the Dataset Provider via a secure email system.

### Verify by:

First identify a select list of IP addresses and an email for which the data will be uploaded and a secure upload token sent. Open the data ingress volume.

1. Ensure that the secure upload token is sent only to the email address provided and via a secure email system
  + a) :white_check_mark: **Verify:** that email system is secure
  + b) :white_check_mark: **Verify:** that a secure upload token can be created with write-only permissions

2. Ensure that data ingress works for connections from within the accepted IP address and does not work for connections outside the IP address, even if the correct upload token is present.
  + a) Identify a test device that will have a whitelisted IP address
  + b) Generate a secure upload token with write-only permissions with limited time period
  + c) Attempt to write to the ingress volume via the test device
  + d) :camera: **Verify:** that writing succeeds
  + e) :camera: **Verify:** that one is unable to view or download from ingress
  + f) Switch to a device that lacks a whitelisted IP address
  + g) Attempt to write to the ingress volume via the test device
  + h) :camera: **Verify:** that the access token fails.

3. Check the token duration and ensure that the upload fails if the duration has expired.
  + a) Create a write-only token with short duration
  + b) :white_check_mark: **Verify:** you can connect and write with the token during the duration
  + c) :camera: **Verify:** you cannot connect and write with the token after the duration has expired

4. Check that the overall ingress works by uploading different kinds of files, e.g. data, images, scripts (if appropriate).

## 8. Storage volumes and egress

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

1. Confirm that a user is able to read the different storage volumes and write to Output and Home
  + a) Login to a DSVM as a non privileged user account via the remote desktop web client
  + b) Open up a file explorer and search for the various storage volumes
  + c) :white_check_mark: **Verify:** that the different storage volumes exist and can be read (opened)
  + d) :white_check_mark: **Verify:** that one can write (move files to) Output and Home
  + e) :white_check_mark: **Verify:** that one cannot write (move files to) the other storage volumes or to outside the environment
2. Confirming that the different volumes exist on the Data Server and that logging on requires domain admin permissions
  + a) Login as domain admin to the SRE Data Server. IP address can be found `RG_SRE_DATA` -> `DAT-SRE-<sreID>`
  + b) Go to `This PC`
  + c) :camera: **Verify:** the volumes exist
  + d) :camera: **Verify:** that a user has written a file to the Output storage volume
  + e) :camera: **Verify:** that a written file can be taken out of the environment

## 9. Software Ingress

### We claim:

The base data science virtual machine provided in the secure analysis Environments comes with a wide range of common data science software pre-installed, as well as package mirrors. For other kinds of software this must be ingressed seperately.

Ingressed software is stored in a holding zone until approved to be added for user access.

### Which means:

For lower tier environments, outbound internet access means users can directly ingress their software from the internet. For higher tier environments we use alternative means.

+ Installation during deployment
  + If known in advance, software can be installed during DSVM deployment whilst there is still internet access, but before project data is added. Once the software is installed, the DSVM is ingressed into the environment with a one way lock.
+ Installation after deployment
  + Once a DSVM has been deployed into the analysis environment it cannot be moved out. There is no outbound internet access.
  + Software is ingressed in a similar manner to data. Researchers are provided temporary write-only access to the software ingress volume (external mode). The access is then revoked and the software is then reviewed. If it passes review, the software ingress volume is changed to provide researchers with read-only access to the environment (internal mode).
  + If the software requires administrator rights to install, a System Manager must do this. Otherwise, the researcher can do this themselves.

### Verify by:

During deployment:

1. Check that one can install software during deployment by using outbound internet
2. Check that outbound internet is closed before adding any project data

After deployment:

3. Check that outbound internet access on the DSVM is closed off with the following tests:
  + a) Check the network rules block
  + b) Attempt to access some of your favourite websites (and fail)
  + c) Attempt to download some software via terminal (and fail)
4. Check that the software ingress volume works correctly:
  + a) Check that the volume can be changed to external mode and that the researcher can write (but not read) the volume
  + b) Check that we can revoke write access successfully
  + c) Check that we can view software that has been written to the volume and that only administrators can read the volume
  + d) Check that the volume can be changed to internal mode so that other researchers can read it (but not write)
  + e) Check that software that requires administraor rights to install, can only be run by a System manager.

## 10. Package mirrors

### We claim:

Tier 2: User can access full package mirrors

Tier 3: User can only access whitelisted package mirrors

### This means:

Tier 2: The user can access any package included within our mirrors. They can freely use these packages without restriction.

Tier 3: The user can only access a specific set of packages that we have agreed with. They will be unable to download any package not on the whitelist.

### Verify by:

Tier 2:

1. Download packages from the full mirror.
  + a) Login as a user into a DSVM via remote desktop web client
  + b) Open up a terminal
  + c) Attempt to install any package that is not included at base

Tier 3:

2. Download packages on the whitelist
  + a) Login as a user into a DSVM via remote desktop web client
  + b) Check that the package is not installed on the VM `sudo apt list <package>` but on the whitelist
  + c) Attempt to download the package
  + d) :white_check_mark: **Verify:** the download succeeds
  + e) Take a package that is not included in the whitelist
  + f) Attempt to download the package
  + g) :white_check_mark: **Verify:** the download fails

## 11. Azure Firewalls

### We claim:

An Azure Firewall ensures that the administrator VMs have the minimal level of internet access required to function.

### Which means:

Whilst all user access VMs are entirely blocked off from the internet, this is not the case for administrator access VMs such as the SHM-DC, SRE DATA server. An Azure Firewall governs the internet access provided to these VMs, limiting them mostly to downloading Windows updates.

### Verify by:

1. Admin has limited access to the internet
  + a) Connect to an administrator VM such as the SHM-DC
  + b) Attempt to connect to your favourite non standard site
  + c) :camera: **Verify:** connection fails
2. Admin can download Windows updates
  + a) Connect to an administrator VM such as the SHM-DC
  + b) Click on `Start -> Settings-> Update & Security`
  + c) Click the `Download` button
  + d) :camera: **Verify:** download and update successful

## 12. Non technical security implementation

### User addition sign-off

Non technical implementation

### Data classification sign-off

Non technical implementation

### Software ingress sign-off

Non technical implementation
