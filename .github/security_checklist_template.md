# Security checklist
Running on SHM/SREs deployed using commit XXXXXXX

## Summary
+ :white_check_mark: N tests passed
- :partly_sunny: N tests partially passed (see below for more details)
- :fast_forward: N tests skipped (see below for more details)
- :x: N tests failed (see below for more details)

## Details
Some security checks were skipped since:
- No managed device was available
- No access to a physical space with its own dedicated network was possible

### Multifactor Authentication and Password strength
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Check that the SRE standard user cannot access the apps
  + <details><summary>:camera: <b>Verify before adding to group:</b> Microsoft Remote Desktop: Login works but apps cannot be viewed</summary>
    <img src=""/>
    </details>
  + <details><summary>:camera: <b>Verify before adding to group:</b> Guacamole: User is prompted to setup MFA</summary>
    <img src=""/>
    </details>

+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x:  Check that adding the **SRE standard user** to the SRE group on the domain controller does not give them access
  + <details><summary>:camera: <b>Verify after adding to group:</b> Microsoft Remote Desktop: Login works and apps can be viewed</summary>
    <img src=""/>
    </details>
  + <details><summary>:camera: <b>Verify after adding to group:</b> Microsoft Remote Desktop: attempt to login to DSVM Main (Desktop) fails</summary>
    <img src=""/>
    </details>
  + <details><summary>:camera: <b>Verify before adding to group:</b> Guacamole: User is prompted to setup MFA</summary>
    <img src=""/>
    </details>

+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Check that the **SRE standard user** is able to successfully set up MFA
  + <details><summary>:camera: <b>Verify:</b> successfully set up MFA</summary>
    <img src=""/>
    </details>

+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Check that the **SRE standard user** can authenticate with MFA
  + <details><summary>:camera: <b>Verify:</b> Guacamole: respond to the MFA prompt</summary>
    <img src=""/>122043131-47bc8080-cddb-11eb-8578-e45ab3efaef0.png">
    </details>
  + <details><summary>:camera: <b>Verify:</b> Microsoft Remote Desktop: attempt to log in to DSVM Main (Desktop) and respond to the MFA prompt</summary>
    <img src=""/>122043131-47bc8080-cddb-11eb-8578-e45ab3efaef0.png">
    </details>

+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Check that the **SRE standard user** can access the DSVM desktop
  + <details><summary>:camera: <b>Verify:</b> Microsoft Remote Desktop: connect to <i>DSVM Main (Desktop)</i></summary>
    <img src=""/>
    </details>
  + <details><summary>:camera: <b>Verify:</b> Guacamole: connect to <i>Desktop: Ubuntu0</i> </summary>
    <img src=""/>
    </details>

### Isolated Network
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Connect to the SHM DC and NPS if connected to the SHM VPN
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Fail to connect to the SHM DC and NPS if not connected to the SHM VPN
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Fail to connect to the internet from within a DSVM on the SRE network.
  + <details><summary>:camera: <b>Verify:</b> Connection fails</summary>
    <img src=""/>122045859-8142bb00-cdde-11eb-920c-3a162a180647.png">
    </details>
  + <details><summary>:camera: <b>Verify:</b> that you cannot access a website using curl</summary>
    <img src=""/>
    </details>
  + <details><summary>:camera: <b>Verify:</b> that you cannot get the IP address for a website using nslookup</summary>
    <img src=""/>
    </details>
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Check that users cannot connect between two SREs within the same SHM, even if they have access to both SREs
  + <details><summary>:camera: <b>Verify:</b> SSH connection fails</summary>
    <img src=""/>
    </details>
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Network rules are set appropriately to block outgoing traffic
  + <details><summary>:camera: <b>Verify:</b> access rules</summary>
    <img src=""/>
    </details>

### User devices
#### Tier 2:
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Connection succeeds from a personal device with an allow-listed IP address
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: No managed device available to check connection

#### Tier 3:
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: No managed device available to check user lacks root access
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Connection succeeds from a personal device with an allow-listed IP address
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: No managed device available to check connection with an allow-listed IP address

#### Tiers 2+:
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Network rules permit access only from allow-listed IP addresses
  + <details><summary>:camera: <b>Verify:</b> access rules</summary>
    <img src=""/>
    </details>
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: All non-deployment NSGs have rules denying inbound connections from outside the Virtual Network

### Physical security
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: No secure physical space available so connection from outside was not tested
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: No secure physical space available so connection from inside was not tested
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Check the network IP ranges corresponding to the research spaces and compare against the IPs accepted by the firewall.
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: No secure physical space available so confirmation of physical measures was not tested

### Remote connections

+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Unable to connect as a user to the remote desktop server via SSH
  + <details><summary>:camera: <b>Verify:</b> SSH connection by FQDN fails</summary>
    <img src=""/>
    </details>
  + <details><summary>:camera: <b>Verify:</b> SSH connection by public IP address fails</summary>
    <img src=""/>
    </details>
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: The remote desktop server is the only SRE resource with a public IP address

### Copy-and-paste
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Unable to paste local text into a DSVM
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Unable to copy text from a DSVM
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Copy between VMs in an SRE succeeds

### Data ingress
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **System administrator:** secure upload token successfully created with write-only permissions
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **System administrator:** token was sent using a secure, out-of-band communication channel (e.g. secure email)
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **Data Provider:** uploading a file from an allow-listed IP address succeeds
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **Data Provider:** downloading a file from an allow-listed IP address fails
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **Data Provider:** uploading a file from an non-allowed IP address fails
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **Data Provider:** connection during lifetime of short-duration token succeeds
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **Data Provider:** connection after lifetime of short-duration token fails
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **Data Provider:** uploading different file types succeeds

### Storage volumes and egress
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **SRE standard user** can read and write to the `/output` volume
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **SRE standard user** can only read from the `/data` volume
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **SRE standard user** can read and write to their directory in `/home`
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **SRE standard user** can read and write to the `/shared` volume
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **System administrator:** can see the files ready for egress
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **System administrator:** can download egress-ready files

### Software Ingress
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **SRE standard user** expected software tools are installed
  + <details><summary>:camera: <b>Verify:</b> DBeaver, RStudio, PyCharm and Visual Studio Code available</summary>
    <img src=""/>122056611-0a132400-cdea-11eb-9087-385ab296189e.png">
    </details>
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **System administrator:** secure upload token successfully created with write-only permissions
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **Data Provider:** uploading is possible only during the token lifetime
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **System administrator:** uploaded files are readable and can be installed on the DSVM
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: **SRE standard user** uploaded files are readable but cannot be installed on the DSVM

### Package mirrors

#### Tier 2:
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Can install any packages
  + <details><summary>:camera: <b>Verify:</b> botocore can be installed</summary>
    <img src=""/>
    </details>

#### Tier 3:
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Can install only allow-listed packages
  + <details><summary>:camera: <b>Verify:</b> aero-calc can be installed; botocore cannot be installed</summary>
    <img src=""/>
    </details>

### Azure firewalls
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Admin has limited access to the internet
  + <details><summary>:camera: <b>Verify:</b> SHM DC cannot connect to google</summary>
    <img src=""/>122067607-ff5d8c80-cdf3-11eb-8e20-a401faba0be4.png">
    </details>
+ :white_check_mark:/:partly_sunny:/:fast_forward:/:x: Admin can download Windows updates
  + <details><summary>:camera: <b>Verify:</b> Windows updates can be downloaded</summary>
    <img src=""/>122067641-071d3100-cdf4-11eb-9dc8-03938ff49e3a.png">
    </details>
