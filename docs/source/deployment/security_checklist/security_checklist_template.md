# Security checklist

Running on SHM/SREs deployed using commit xxxxxx

## Summary

- :white_check_mark: x tests passed
- :partly_sunny: x tests partially passed (see below for more details)
- :fast_forward: x tests skipped (see below for more details)
- :x: x tests failed (see below for more details)

## Details

- Any additional details as referred to in the summary

### Multifactor Authentication and Password strength

- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Check: Users can reset their own password
    - <summary><b>Verify that:</b> User can reset their own password</summary>
    <img src="…"/>
- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Check: non-registered users cannot connect to any SRE workspace
    - <summary> <b>Verify that:</b> User can authenticate but cannot see any workspaces</summary>
    <img src="…"/>
- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Check: registered users can see SRE workspaces
    - <summary> <b>Verify that:</b> User can authenticate and can see workspaces</summary>
    <img src="…"/>
- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Check: Authenticated user can access workspaces
    - <summary> <b>Verify that:</b> You can connect to any workspace</i> </summary>
    <img src="…"/>

### Isolated Network

- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Fail to connect to the internet from a workspace
    - <summary> <b>Verify that:</b> Browsing to the service fails</summary>
    <img src="…"/>
    - <summary> <b>Verify that:</b> You cannot access the service using curl</summary>
    <img src="…"/>
    - <summary> <b>Verify:</b> You cannot get the IP address for the service using nslookup</summary>
    <img src="…"/>

### User devices

#### Tier 2:

- Connect to the environment using an allowed IP address and credentials
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> Connection succeeds
- Connect to the environment from an IP address that is not allowed but with correct credentials
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> Connection fails

#### Tier 3:

- All managed devices should be provided by a known IT team at an approved organisation.
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> the IT team of the approved organisation take responsibility for managing the device.
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> the user does not have administrator permissions on the device.
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> allowed IP addresses are exclusive to managed devices.
- Connect to the environment using an allowed IP address and credentials
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> Connection succeeds
- Connect to the environment from an IP address that is not allowed but with correct credentials
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> Connection fails

#### Tiers 2 and above:

- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Network rules permit access only from allow-listed IP addresses
    - In the Azure portal navigate to the Guacamole application gateway NSG for this SRE shm-<SHM NAME>-sre-<SRE NAME>-nsg-application-gateway
    - <summary> <b>Verify that:</b> the NSG has network rules allowing Inbound access from allowed IP addresses only</summary>
    <img src="…"/>
- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: all other NSGs have an inbound Deny All rule and no higher priority rule allowing inbound connections from outside the Virtual Network

### Physical security

#### Tier 3 only

- Attempt to connect to the Tier 3 SRE web client from home using a managed device and the correct VPN connection and credentials.
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that</b>: connection fails.
- Attempt to connect from research office using a managed device and the correct VPN connection and credentials.
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that</b>: connection succeeds
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that</b>: the network IP ranges corresponding to the research spaces correspond to those allowed by storage account firewall
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that</b>: physical measures such as screen adaptions or desk partitions are present if risk of visual eavesdropping is high

### Remote connections

- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Unable to connect as a user to the remote desktop server via SSH
    - <summary> <b>Verify that:</b> SSH login by fully-qualified domain name fails</summary>
    <img src="…"/>
    - <summary> <b>Verify that:</b> SSH login by public IP address fails</summary>
    <img src="…"/>

- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> the remote desktop web client application gateway (shm-<SHM ID>-sre-<SRE ID>-ag-entrypoint) and the firewall are the only SRE resources with public IP addresses.

### Copy-and-paste

- Unable to paste text from a local device into a workspace
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> paste fails
- Unable to copy text from a workspace to a local device
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> paste fails

### Data ingress

- Check that the **System Manager** can send an upload token to the **Dataset Provider Representative**
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> the upload token is successfully created.
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> you are able to send this token using a secure mechanism.
- Ensure that data ingress works only for connections from the accepted IP address range
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> writing succeeds by uploading a file
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> attempting to open or download any of the files results in the following error: "Failed to start transfer: Insufficient credentials" under the Activities pane at the bottom of the MS Azure Storage Explorer window.
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> the access token fails when using a device with a non-allowed IP address
- Check that the upload fails if the token has expired
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> you can connect and write with the token during the duration
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> you cannot connect and write with the token after the duration has expired
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b>the data ingress process works by uploading different kinds of files, e.g. data, images, scripts (if appropriate)

### Data egress

- Confirm that a non-privileged user is able to read the different storage volumes and write to output
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> the `/mnt/output` volume exists and can be written to
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> the permissions of other storage volumes match that described in the user guide
- Confirm that <b>System Manager</b> can see and download files from output
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> you can see the files written to the `/mnt/output` storage volume.
    - :white_check_mark:/:partly_sunny:/:fast_forward:/:x: <b>Verify that:</b> a written file can be taken out of the environment via download

### Software package repositories

#### Tier 2:

- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Can install any packages
    - <summary> <b>Verify that:</b> pytz can be installed</summary>
    <img src="…"/>
    - <summary> <b>Verify that:</b> awscli can be installed</summary>
    <img src="…"/>

#### Tier 3:

- :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Can install only allow-listed packages
    - <summary> <b>Verify:</b> pytz can be installed</summary>
    <img src="…"/>
    - <summary> <b>Verify:</b> awscli cannot be installed</summary>
    <img src="…"/>
