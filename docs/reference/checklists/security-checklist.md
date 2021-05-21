# Security evaluation checklist

In this check list we aim to do the following things:

+ Establish our current claims about the Data Safe Haven
+ Establish what these security claims mean in terms of implementation
+ How we can verify that we actually do what we say

This diagram shows the security standards we're trying to meet for Data Safe Haven Secure Research Environments (SREs). The security checklist currently focuses on checks that can verify these security requirements for tier 2+ SREs (with some steps noted as specific to a tier):

<p align="center">
    <img src="../../images/security_checklist/recommended-controls.png" width="80%" title="recommended-controls">
</p>

## How to use this checklist

+ Ensure you have an SHM and attached SRE(s) that you wish to test.
  + Note: Some parts of the checklist are only relevant when there are multiple SREs attached to the same SHM
+ Work your way through the actions described in each section, taking care to notice each time you see a :camera: or a :white_check_mark: and the word **Verify**:
  + :camera: Where you see the camera icon, there should be accompanying screenshot(s) of evidence for this item in the checklist (you may wish to save your own equivalent screenshots as evidence)
  + :white_check_mark: This indicates a checklist item for which a screenshot is either not appropriate or  difficult

## Contents

+ [Prerequisites](#prerequisites)
+ [Multifactor Authentication and Password strength](#1-multifactor-authentication-and-password-strength)
+ [Isolated Network](#2-isolated-network)
+ [User devices](#3-user-devices)
+ [Physical security](#4-physical-security)
+ [Remote connections](#5-remote-connections)
+ [Copy-and-paste](#6-copy-and-paste)
+ [Data Ingress](#7-data-ingress)
+ [Data Egress](#8-data-egress)
+ [Software ingress](#9-software-ingress)
+ [Package mirrors](#10-package-mirrors)
+ [Azure Firewalls](#11-azure-firewalls)

## Prerequisites

If you haven't already, you'll need download a VPN certificate and configure [VPN access](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#download-a-client-vpn-certificate-for-the-safe-haven-management-network) for the SHM that the SRE you're testing uses and make sure you can log in to the [domain controller (DC1) via Remote Desktop](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#configure-the-first-domain-controller-via-remote-desktop), as well as the [network policy server (NPS)](../../tutorial/deployment_tutorials/how-to-deploy-shm.md#log-in-to-the-nps-vm-using-microsoft-remote-desktop).

## 1. Multifactor Authentication and Password strength

### We claim:

Users are required to authenticate with Multi Factor Authentication (MFin order to access the secure analysis environment.

Passwords are strong

### Which means:

Users must set up MFA before accessing the secure analysis environment. Users cannot access the environment without MFA. Users are strongly advised to create passwords of a certain strength.

### Verify by:

+ Create a new user without MFA and check that the user cannot access the apps
  + Following the [SRE deployment guide](../../tutorial/deployment_tutorials/how-to-deploy-sre.md#optional-set-up-a-non-privileged-user-account) for setting up a non privileged user account, create an account, then check the following before (and after (adding them to the `SG <SRE ID> Research Users` group.
  + Visit https://aka.ms/mfasetup in an incognito browser
  + Attempt to login and reset password, but **do not complete MFA** (see [these steps](../../how_to_guides/user_guides/user-guide.md#closed_lock_with_key-set-a-password))
  + Login to the remote desktop web client (`https://<SRE ID>.<safe haven domain> (eg. https://sandbox.dsgroupdev.co.uk/`)
  + <details><summary>:camera: <b>Verify before adding to group:</b> Login works but apps cannot be viewed</summary> !<img width="549" alt="1-1d-cropped" src="https://user-images.githubusercontent.com/5486164/118115124-73b1a400-b3e0-11eb-92d3-aab5aa90d89c.png"></details>
  + <details><summary>:camera: <b>Verify after adding to group:</b> Login again and check that apps can now be viewed</summary> <img width="549" alt="1-1e-cropped" src="https://user-images.githubusercontent.com/5486164/118115140-7b714880-b3e0-11eb-9235-d2d8c75d75a6.png"></b>
+ <details><summary>:camera: <b>Verify:</b> attempt to login to DSVM Main (Desktop) fails</summary> <img width="619" alt="Screenshot 2021-03-30 at 14 14 34" src="https://user-images.githubusercontent.com/5486164/112995318-006f0e00-9163-11eb-9310-dca76d800dca.png"></details>
+ Check that the user is able to successfully set up MFA
  + Visit https://aka.ms/mfasetup again
  + Login as the user you set up
  + :white_check_mark: **Verify:** user guided to set up MFA
  + Set up MFA as per [the user guide instructions](../../how_to_guides/user_guides/user-guide.md#door-set-up-multi-factor-authentication)
  + :camera: **Verify:** successfully set up MFA ![Screenshot 2021-03-30 at 14 27 17](https://user-images.githubusercontent.com/5486164/112996434-13cea900-9164-11eb-9ddd-db638c64846a.png)
+ Check that MFA is working as we expect
  + :camera: **Verify:** login to the portal using the user account and check that MFA requested <img width="418" alt="Screenshot 2021-03-30 at 14 32 36" src="https://user-images.githubusercontent.com/5486164/112998020-8ab87180-9165-11eb-9933-b0e2258d2c9a.png">
  + Login into the remote desktop web client (`https://<SRE ID>.<safe haven domain> (eg. https://sandbox.dsgroupdev.co.uk/`)
  + :white_check_mark: **Verify:** that MFA is requested on first attempt to log in to DSVM Main (Desktop)

## 2. Isolated Network

### We claim:

The DSH Virtual Network is isolated from external connections (both tier 2 and 3)

### Which means:

Users cannot access any part of the network without already being in the network. Being part of the network involves connecting using an SHM specific Management VPN.

Whilst in the network, one cannot use the internet to connect outside the network.

SREs in the same SHM are still isolated from one another.

### Verify by:

+ Connect to the SHM DC, NPS, Data server if and only if connected to the SHM VPN:
  + Connect to the SHM VPN
  + Connect to the SHM DC
  + Connect to the SHM NPS
  + :white_check_mark: **Verify:** Connection works
  + Disconnect from the SHM VPN
  + Attempt to connect to the SHM DC and NPS again
  + :white_check_mark: **Verify:** Connection fails
+ Be unable to connect to the internet from within a DSVM on the SRE network.
  + Login as a user to a DSVM from within the SRE by using the web client.
  + Choose your favourite three websites and attempt to access the internet using a browser
  + :camera: **Verify:** Connection fails <img width="938" alt="2-2c-cropped" src="https://user-images.githubusercontent.com/5486164/118115368-c25f3e00-b3e0-11eb-8afd-6d7ab86d6de0.png">
  + :camera: **Verify:** type `curl <website>` into terminal and check that you get a response like: `curl: (6) Could not resolve <website>` <img width="539" alt="Screenshot 2021-03-30 at 15 57 05" src="https://user-images.githubusercontent.com/5486164/113010241-99585600-9170-11eb-9345-49cc39558dce.png">
+ Check that users cannot connect between two SREs within the same SHM, even if they have access to both SREs
  + Ensure you have two SREs managed by the same SHM
  + Connect to a DSVM in SRE A as a user by using the web client. On a separate browser window, do the same for SRE B.
  + Attempt to copy and paste a file from one SRE desktop to another
  + :white_check_mark: **Verify:** Copy and paste is not possible
  + Attempt to connect to SRE B's DSVM via SSH from SRE A:
  + Click on `DSVM Main (SSH)` from the `All Resources` tab of the web client window you have open for SRE A
  + Right click on the PuTTY terminal and click `New Session...`
  + Enter the IP address for SRE B (you can find this by clicking `DSVM Main (SSH)` in the SRE B window you have open)
  + Click `Open`
  + :camera: **Verify:** Connection fails with `Network error: Connection timed out` <img width="685" alt="Screenshot 2021-04-01 at 10 07 17" src="https://user-images.githubusercontent.com/5486164/113274096-359b6d80-92d5-11eb-8e8a-024514178edf.png">
+ Check that the network rules are set appropriately to block outgoing traffic
  + Visit the portal and find `NSG_SHM_<SHM ID>_SRE_<SRE ID>_COMPUTE`, then click on the `Outbound security rules` under `Settings`
  + :camera: **Verify:** There exists an `DenyInternetOutbound` rule with Destination `Internet` and Action `Deny` and no higher priority rule allows connection to the internet. <img width="1896" alt="Screenshot 2021-04-01 at 12 00 25" src="https://user-images.githubusercontent.com/5486164/113284898-3686cc00-92e2-11eb-8e29-adc9e55ca6e3.png">

## 3. User devices

### We claim:

At tier 3, only managed devices can connect to the DSH environment.

At tier 2, all kinds of devices can connect to the DSH environment (with VPN connection and correct credentials).

### This means

A managed device is a device provided by a partner institution in which the user does not have admin or root access.

Network rules for the higher tier Environments can permit access only from Restricted network IP ranges that only permit managed devices to connect.

### Verify by:

For tier 2:

+ One can connect regardless of device as long as one has the correct VPN and credentials
  + Using a personal device, connect to the environment using the correct VPN and credentials
  + :white_check_mark: **Verify:** Connection succeeds
  + Using a managed device, connect to the environment using the correct VPN and credentials.
  + :white_check_mark: **Verify:** Connection succeeds
+ There are are network rules permitting access only from the Turing Tier 2 and Tier 3 VPNs
  + Navigate to the NSG for this SRE in the portal: `NSG_SHM_<SHM ID>_SRE_<SRE ID>_RDS_SERVER`
  + :camera: **Verify:** The `RDS` NSG has network rules allowing **inbound** access from the IP address of the tier 2 SRE <img width="1028" alt="Screenshot 2021-04-06 at 13 42 09" src="https://user-images.githubusercontent.com/5486164/113712330-e8a50600-96dd-11eb-9b09-4076830cf84c.png">
  + :white_check_mark: **Verify:** All other NSGs have an inbound Deny All rule and no higher priority rule allowing inbound connections from outside the Virtual Network.

For tier 3:

+ A device is managed by checking user permissions and where the device has come from. We should check that it is managed by the partner institution's IT team.
  + Check that the device is managed by the partner institution IT team
  + :white_check_mark: **Verify:** The user lacks root access
+ A device is able to connect to the environment if and only if it is managed (with correct VPN and credentials)
  + Using a personal device, attempt to connect to the environment using the correct VPN and credentials
  + :white_check_mark: **Verify:** Connection fails
  + Using a managed device, attempt to connect to the environment using the correct VPN and credentials
  + :white_check_mark: **Verify:** Connection succeeds

## 4. Physical security

### We claim:

At tier 3 access is limited to certain research office spaces

### Which means:

Medium security research spaces control the possibility of unauthorised viewing. Card access or other means of restricting entry to only known researchers (such as the signing in of guests on a known list) is required. Screen adaptations or desk partitions can be adopted in open-plan spaces if there is a high risk of "visual eavesdropping".

Firewall rules for the Environments can permit access only from Restricted network IP ranges corresponding to these research spaces.

### Verify by:

For tier 3:

+ Connection outside of the research office space is not possible.
  + Attempt to connect to the tier 3 SRE web client from home using a managed device and the correct VPN connection and credentials
  + :white_check_mark: **Verify:** connection fails
+ Connection from within the research office space is possible.
  + Attempt to connect from research office using a managed device and the correct VPN connection and credentials
  + :white_check_mark: **Verify:** connection succeeds
+ :white_check_mark: **Verify:** Check the network IP ranges corresponding to the research spaces and compare against the IPs accepted by the firewall.
+ :white_check_mark: **Verify:** Physically confirm that measures such as screen adaptions or desk partitions are present.

## 5. Remote connections

### We claim:

Connections can only be made via remote desktop (Tier 2+)

### This means

User can connect via remote desktop but cannot connect through other means such as SSH

### Verify by:

+ Unable to connect as a non-admin user to the DSVM via SSH
  + Find the public IP address for the `RDG-SRE-<SRE ID>` VM by searching for this VM in the portal, then looking at `Connect` under `Settings`.
  + :camera: **Verify:** ssh login fails: `ssh user.name@<SRE ID>.<Domain>.co.uk@<Public IP>` (e.g. `ssh john.doe@testa.dsgroupdev.co.uk@<Public IP>`) ![Screenshot 2021-04-13 at 11 04 35](https://user-images.githubusercontent.com/5486164/114535742-45f20780-9c48-11eb-9ccc-71351e776d8c.png)
  + :white_check_mark: **Verify:** The RDS server (`RDG-SRE-<SRE ID>`) is the only resource with a public IP address

## 6. Copy-and-paste

### We claim:

Copy and paste is disabled on the remote desktop

### Which means:

One cannot copy something from outside the network and paste it into the network. One cannot copy something from within the network and paste it outside the network.

### Verify by:

+ One is unable to copy some text from outside the network, into a DSVM and vice versa
  + Copy some text from your deployment device
  + Login to a DSVM via the remote desktop web client
  + Open up a notepad or terminal on the DSVM and attempt to paste the text to it.
  + :white_check_mark: **Verify:** paste fails
  + Write some next in the note pad or terminal of the DSVM and copy it
  + Attempt to copy the text externally to deployment device (e.g. into URL of browser)
  + :white_check_mark: **Verify:** paste fails
+ One can copy between VMs inside the network
  + Login to a DSVM via the remote desktop web client
  + Open up a notepad or terminal on the DSVM and attempt to paste the text to it.
  + Connect to another DSVM (for example, the SSH connection) via the remote desktop web client (as a second tab)
  + Attempt to paste the text to it.
  + :white_check_mark: **Verify:** paste succeeds

## 7. Data ingress

### We claim:

All data transfer to the Turing should be via our secure data transfer process, which provides the Dataset Provider time-limited, write-only access to a dedicated data ingress volume from a specific location.

Data is stored in a holding zone until approved to be added for user access.

### This means

Prior to access to the ingress volume being provided, the Dataset Provider Representative must provide the IP address(es) from which data will be uploaded and an email address to which a secure upload token can be sent. Once these details have been received, the Turing will open the data ingress volume for upload of data.

To minimise the risk of unauthorised access to the dataset while the ingress volume is open for uploads, the following security measures are in place:

+ Access to the ingress volume is restricted to a limited range of IP addresses associated with the Dataset Provider and the Turing.
+ The Dataset Provider receives a write-only upload token. This allows them to upload, verify and modify the uploaded data, but does not viewing or download of the data. This provides protection against an unauthorised party accessing the data, even they gain access to the upload token.
+ The upload token expires after a time-limited upload window.
+ The upload token is transferred to the Dataset Provider via a secure email system.

### Verify by:

To test all the above, you will need to act both as the administrator and data provider:

+ Generate the secure upload token and check it can be sent to the email address provided by the data provider via a secure email system
  + :white_check_mark: **Verify:** that a secure upload token can be created with write-only permissions, by following the instructions in the [administrator document](../../how_to_guides/administrator/how-to-be-a-sysadmin.md#data-ingress), using the IP address of your own device in place of that of the data provider
  + :white_check_mark: **Verify:** that you are able to send a secure email containing this token (e.g. send it to your own email for testing purposes)

+ Ensure that data ingress works for connections from within the accepted IP address and does not work for connections outside the IP address, even if the correct upload token is present.
  + Ensure you're working from a device that will have a whitelisted IP address
  + Using the secure upload token with write-only permissions and limited time period that you set up in the previous step, follow the [ingress instructions for the data provider](../../how_to_guides/data_provider/how-to-ingress-data-as-provider.md)
  + :white_check_mark: **Verify:** that writing succeeds by uploading a file
  + :white_check_mark: **Verify:** that attempting to open or download any of the files results in the following error: `Failed to start transfer: Insufficient credentials.` under the `Activities` pane at the bottom of the MS Azure Storage Explorer window
  + Switch to a device that lacks a whitelisted IP address (or change your IP with a VPN)
  + Attempt to write to the ingress volume via the test device
  + :white_check_mark: **Verify:** that the access token fails.

+ Check the token duration and ensure that the upload fails if the duration has expired.
  + Create a write-only token with short duration
  + :white_check_mark: **Verify:** you can connect and write with the token during the duration
  + :white_check_mark: **Verify:** you cannot connect and write with the token after the duration has expired

+ :white_check_mark: **Verify:** Check that the overall ingress works by uploading different kinds of files, e.g. data, images, scripts (if appropriate).

## 8. Data egress

### We claim:

SREs contain an `/output` volume, in which SRE users can store data designated for egress.

### This means:

A domain administrator can view and download data in the `/output` volume via Azure Storage Explorer.

### Verify by:

+ Confirm that a user is able to read the different storage volumes and write to Output
  + Login to a DSVM as a non privileged user account via the remote desktop web client
  + Open up a file explorer and search for the various storage volumes
  + :white_check_mark: **Verify:** that the `/output` volume exists and can be read and written to
  + :white_check_mark: **Verify:** that the permissions of other storage volumes match that described in the [user guide](../../how_to_guides/user_guides/user-guide.md#open_file_folder-shared-directories-within-the-sre)
+ Confirm that the different volumes exist in blob storage and that logging on requires domain admin permissions
  + Follow the instructions in the [administrator document](../../how_to_guides/administrator/how-to-be-a-sysadmin.md#data-egress) on how to access files set for egress with Azure Storage Explorer
  + :white_check_mark: **Verify:** You can see the files written to the Output storage volume (including any you created as a non-privileged user in step 1)
  + :white_check_mark: **Verify:** that a written file can be taken out of the environment via download

## 9. Software Ingress

### We claim:

The base data science virtual machine provided in the secure analysis Environments comes with a wide range of common data science software pre-installed, as well as package mirrors. For other kinds of software this must be added separately via ingress.

Software is stored in a holding zone until approved to be added for user access.

### Which means:

For tier 0/1 environments, outbound internet access means users can directly download their software from the internet. For tier 2+ environments we use the secure data transfer process.

+ Installation during deployment
  + If known in advance, software can be installed during DSVM deployment whilst there is still internet access, but before project data is added. Once the software is installed, the DSVM undergoes ingress into the environment with a one way lock.
+ Installation after deployment
  + Once a DSVM has been deployed into the analysis environment it cannot be moved out. There is no outbound internet access.
  + Software is added via ingress in a similar manner to data. Researchers are provided temporary write-only access to the software ingress volume (external mode). The access is then revoked and the software is then reviewed. If it passes review, the software ingress volume is changed to provide researchers with read-only access to the environment (internal mode).
  + If the software requires administrator rights to install, a System Manager must do this. Otherwise, the researcher can do this themselves.

### Verify by:

+ Check that software was installed during deployment (via outbound internet), but that outbound internet access on the DSVM is closed off after deployment:
  + :camera: **Verify:** Connect as a user to a tier 2+ SRE via the webclient and check that GitLab is present (GitLab being an example of software installed during deployment via outbound internet access) ![Screenshot 2021-05-13 at 09 46 40](https://user-images.githubusercontent.com/5486164/118102097-43620980-b3d0-11eb-838a-1973389865af.png)
+ Check that it's possible to grant and revoke software ingress capability by following the instructions in the [Safe Haven Administrator Documentation](../../how_to_guides/administrator/how-to-be-a-sysadmin.md#software-ingress):
  + :white_check_mark: **Verify:** You can generate a temporary write-only upload token
  + :white_check_mark: **Verify:** You can upload software as a non-admin with this token, but write access is revoked after the temporary token has expired
  + :white_check_mark: **Verify:** Software uploaded to the by a non-admin can be read by administrators
  + :white_check_mark: **Verify:** Check that software that requires administrator rights to install (i.e. anything you can install with `apt`), can only be installed by a System manager (see definition [here](https://arxiv.org/abs/1908.08737)), or at least verify that it cannot when logged in to the DSVM with a non-manager account.

## 10. Package mirrors

### We claim:

Tier 2: User can access full package mirrors

Tier 3: User can only access whitelisted package mirrors

### This means:

Tier 2: The user can access any package included within our mirrors. They can freely use these packages without restriction.

Tier 3: The user can only access a specific set of packages that we have agreed with. They will be unable to download any package not on the whitelist.

### Verify by:

Tier 2:

+ Download packages from the full mirror.
  + Login as a user into a DSVM via remote desktop web client
  + Open up a terminal
  + :camera: **Verify:** You can install any package that is not included at base (for example, try `pip install sklearn`) ![Screenshot 2021-04-13 at 15 04 19](https://user-images.githubusercontent.com/5486164/114565858-96c62800-9c69-11eb-8300-bef6bb169002.png)

Tier 3:

+ Download packages on the whitelist (see the lists in `environment_configs/package_lists`)
  + Login as a user into a DSVM via remote desktop web client
  + Check that the package is not installed on the VM `sudo apt list <package>` but on the whitelist
  + Attempt to download the package
  + :camera: **Verify:** the download succeeds (see screenshot in part g below)
  + Take a package that is not included in the whitelist
  + Attempt to download the package
  + :camera: **Verify:** the download fails ![Screenshot 2021-04-13 at 16 12 00](https://user-images.githubusercontent.com/5486164/114577970-659f2500-9c74-11eb-9a8c-8321cbfb05c0.png)

## 11. Azure Firewalls

### We claim:

An Azure Firewall ensures that the administrator VMs have the minimal level of internet access required to function.

### Which means:

Whilst all user access VMs are entirely blocked off from the internet, this is not the case for administrator access VMs such as the SHM-DC, SRE DATA server. An Azure Firewall governs the internet access provided to these VMs, limiting them mostly to downloading Windows updates.

### Verify by:

+ Admin has limited access to the internet
  + Connect to an administrator VM such as the SHM-DC
  + Attempt to connect to your favourite non standard site
  + :camera: **Verify:** connection fails ![Screenshot 2021-04-06 at 14 42 37](https://user-images.githubusercontent.com/5486164/113720408-800e5700-96e6-11eb-914a-dd176de94c6a.png)
+ Admin can download Windows updates
  + Connect to an administrator VM such as the SHM-DC
  + Click on `Start -> Settings-> Update & Security`
  + Click the `Download` button ![Screenshot 2021-04-06 at 14 47 52](https://user-images.githubusercontent.com/5486164/113721176-340fe200-96e7-11eb-9316-1869a8724e11.png)
  + :camera: **Verify:** download and update successful
