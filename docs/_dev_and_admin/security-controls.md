# Security controls in the Safe Haven

## Connections to and from the Environment

At lower tiers direct inbound connections to resources within the Environment may be permitted.
At higher tiers inbound connections are only permitted via a secure access node (e.g. Microsoft Remote Desktop Services).

A remote desktop connection allowing access to graphical interface applications should be provided to allow researchers to connect to the remote secure analysis Environment. At all but the lowest tiers, this requires two-factor authentication, and, at some tiers, the copy paste function is disabled.

At every tier, long and strong passphrases (for example, at least four randomly chosen dictionary words) should be enforced, and users are trained in the use of keychain managers on their access devices, locked with two-factor authentication, so that the inconvenience of repeatedly typing a long passphrase is mitigated, reducing the risk of users choosing insecure passwords.

At some tiers, we may provide **secure shell** connections using the command line, in addition to the remote desktop.

The text-based access this grants is sufficient for some professional data scientists. The primary driver for this preference is that processes can easily be reproduced based on the commands typed. If not needed, providing a remote desktop interface adds complexity and therefore risk.

At some tiers, specific commands commonly used for copying out data can therefore be blocked for users.

In neither case is the user absolutely prevented from copying out to the device used to access the Environment (with remote desktop software, malicious users can script automated screen-grabs).
However, this can be made difficult in order to deter casual workaround risk, and, at the highest tiers, prevented by only permitting access to the Environment from user devices permanently located within a secure physical Environment.

We therefore believe it will be possible to make secure shell access just as secure as remote desktop access, but this remains a work in progress.

At lower tiers outbound connections from the Environment to the internet and other external resources are permitted.
At higher tiers connections to resources outside the Environment's private network are not permitted.

## Data sharing agreement

This should be a formal data sharing agreement as required under data protection law, drafted with the benefit of legal advice, and should be signed after the initial classification of a work package but before a dataset is received by the Turing.
Where the Dataset Provider is not the owner of all the dataset(s) covered by the data sharing agreement, the agreement must  specify the legal basis under which the Dataset Provider is permitted to share this data with the Turing.
This agreement should include any specific commitments required from Researchers working with the dataset.
The Turing has a template agreement that can be used to minimise the turnaround time and legal effort required.

The classification tier may potentially be raised from that agreed prior to data ingress, once the Investigator and Referee have had a chance to view the actual data.
The classification tier for later work packages in a project may also be higher than that for the original work package, depending on the planned analysis and any additional data required.
We therefore recommend that the data sharing agreement is worded to permit this.

## User lifecycle

Users who wish to have access to the Environment first complete an online form certifying they understand the confidentiality requirements. An account is then created for them within the Turing Environment management system, and the user activates this.

Projects are created in the management system by a Programme Manager, and an Investigator and Project Manager assigned.

Programme Managers and Project Managers may add users to groups corresponding to specific projects or work packages through the management framework.

The Project Manager has the authority to assign Referees and Data Provider Representatives to a project or work package.

At some tiers, new Referees or members of the research team must also be approved by the Dataset Provider Representative.

Before joining a project or work package, Researchers, Investigators and Referees must agree to any additional commitments specific to that project or work package.

Users are removed from a project or work package promptly once their involvement with it ends.

## Software library distributions

Maintainers of shared research computing environments face a difficult challenge in keeping research algorithm libraries and platforms up to date - and in many cases these conflict.
While sophisticated tools to help with this exist, the use of independent virtual environments opens another possibility: downloading the software as needed from package repositories (such as PyPI for Python or CRAN for R), which automate the process of installing and configuring programs.

For lower tiers, with access to the internet, required software packages can be installed directly from their canonical sources on the internet.
For higher tiers, without access to the external internet, this requires maintenance of full or partial mirrors (exact copies) of package repositories inside the Environment.

Use of package mirrors inside the Environment means that the set of default installed packages can be kept to a minimum, reducing the likelihood of encountering package-conflict problems (where a package can be prevented from being installed due to the presence of an existing package with the same name) and saving on System Manager time.

At the the highest tiers a subset of whitelisted packages (packages which are explicitly marked as safe) is maintained. This whitelist can be specific to the work package if required.
At other tiers the full package list is mirrored, but with a short delato provide an opportunity for the wider community to catch any malicious code uploaded to the canonical package mirrors.

## Storage

Which storage volumes exist in the analysis Environment?

A Secure Data volume is a read-only volume that contains the secure data for use in analyses. It is mounted as read-only in the analysis Environments that must access it. One or more such volumes will be mounted depending on how many managed secure datasets the Environment has access to.

A Secure Document volume contains electronically signed copies of agreements between the Data Provider and the Turing.

A Secure Scratch volume is a read-write volume used for data analysis. Its contents are automatically and regularly deleted. Users can clean and transform the sensitive data with their analysis scripts, and store the transformed data here.

An Output volume is a read-write area intended for the extraction of results, such as figures for publication.

The Software volume is a read-only area which contains software used for analysis.

A Home volume is a smaller read-write volume used for local programming and configuration files. It should not be used for data analysis outputs, though this is enforced only in policy, not technically. Configuration files for software in the software volume point to the Home volume.

## User device networks

Our network security model distinguishes three dedicated research networks for
user devices.

+ The open internet (any network outside a partner institution)
+ An Institutional network
+ A Restricted network

An Institutional network corresponds to a network managed by a partner institution.
Guest access may be permitted on such networks (e.g. eduroam), but these guests should be known users.
Access to Environments can be restricted such that access is only allowed by devices which are connected to a particular set of Institutional networks.
However, it is assumed that a wide segment of the research community can access these networks.
This access may also be remote for authorised users (for example, via VPN).

A Restricted network corresponds to a network managed by a partner institution that can support additional controls such as restricting access to a narrower set of users, devices or locations.
Access to Environments can be restricted such that access is only allowed by devices which are connected to a particular set of Restricted networks.
Access to a particular Environment may be permitted from multiple Restricted networks at multiple partner organisations.
This can permit users from multiple organisations to access an Environment, as well permitting users to access the Environment while away from their home institution at another partner institution.
However, remote access to a Restricted network (for example via VPN) is not permitted.

At higher tiers Environment firewall rules permit access only from network IP ranges corresponding to specific Institutional and Restricted networks approved for the Environment.
Note that these restrictions on networks that can access Environments relate to inbound connectivity only.
Separate controls determine whether outbound connections can be made from an Environment and whether inbound connections are permitted directly to resources within the Environment or must be made via a secure access node.
In addition to these netwrok level restrictions, users must additionally authenticate to the Environment in order to access it.

## Physical security

Some data requires a physical security layer around not just the data centre,
but the physical space users are in when they connect to it.

We distinguish three levels of physical security for research spaces:

+ Open research spaces
+ Medium security research spaces
+ High security research spaces

Open research spaces include university libraries, cafes and common rooms.

Medium security research spaces control the possibility of unauthorised viewing.
Card access or other means of restricting entry to only known researchers (such as the signing in of guests on a known list) is required.
Screen adaptations or desk partitions can be adopted in open-plan spaces if there is a high risk of "visual eavesdropping".

Secure research spaces control the possibility of the researcher deliberately removing data.
Devices will be locked to appropriate desks, and neither enter nor leave the space.
Mobile devices should be removed before entering, to block the 'photographic hole', where mobile phones are used to capture secure data from a screen.
Only researchers associated with a secure project have access to such a space.

Firewall rules for the Environments can permit access only from Restricted network IP ranges corresponding to these research spaces.

## User Devices

What devices should researchers use to connect to the Environment?

We define two types of devices:

+ Managed devices
+ Open devices

### Managed devices

Managed devices are devices provided by a partner institution on which the user does not have administrator/root access, with the device instead administered by the institution's IT team.

Managed devices could be provided by the Turing, or one of the partner organisations for a work package.

They have an extensive suite of research software installed.

This includes the ability to install packages for standard programming environments without the need for administrator access.

Researchers can compile and run executables they code in User Space (the portion of system memory in which user processes run).

### Open Devices

These include personal devices such as researcher-owned laptops, but also include devices provided by a partner institution where the user has administrator/root access.

These devices permit the easy use of a wider range of software than managed devices, as well as easier access to peripheral hardware.

However, such devices should not be used to access the highest tier Environments.

Firewall rules for the higher tier Environments can permit access only from Restricted network IP ranges that only permit managed devices to connect.

## The choices

Having described the full model, processes, and lifecycles, we can now enumerate the list of choices that can be made for each Environment.
These are all separately configurable on an environment-by-environment basis.
However, we recommend the following at each tier.

### Software installation

+ At Tier 3 and above, package mirrors (copies of external repositories inside the secure Environment) should include only white-listed software packages.
+ At Tier 2, package mirrors should include all software packages.
+ At Tier 2 and above, all software not available from a package mirror must be installed either at the time the analysis machine is first deployed or by ingressing the software installer as data, with an associated ingress review.
+ At Tier 1 and 0, all software installation should be from the internet.

### Inbound connections

+ At Tier 2 and above, analysis machines and other Environment resources are not accessible directly from client devices. Instead, secure "access nodes" provide secure web-based remote desktop facilities used to indirectly access the analysis Environments (e.g. Microsoft Remote Desktop Services).
+ At Tier 1 and 0, analysis machines and other Environment resources are directly accessible from client devices.
+ At Tier 3 and above Environment access nodes are only available from approved Restricted networks.
+ At Tier 2 Environment access nodes are only be accessible from approved Institutional networks.
+ At Tier 1 and 0 Environment resources are accessible from the open internet

### Outbound connections

+ At Tier 2 and above no connections are permitted from the Environment private network to the internet or other external resources.
+ At Tier 1 and 0 the internet is accessible from inside the Environment.

### Data ingress

+ At Tier 2 and above, the high-security data transfer process is required (i.e. write only access from particular locations for a limited time).
+ At Tier 1 and 0 the use of standard secure data transfer processes (e.g. SCP/SFTP) may be permitted.

### Data egress

+ At Tier 3 and above, the Data Provider Representative, Investigator and Referee are all required to sign off all egress of data or code from the Environment.
+ At Tier 2, only the Investigator and Referee are required to review and approve all egress of data or code from the Environment.
+ At Tier 1 and 0 users are permitted to copy out data when they believe their local device is secure, with the permission of the Investigator.

### Refereeing of classification

Independent Referee scrutiny of data classification is required when the initial classification by the Investigator and Data Provider Representative is Tier 2 or higher.

### Two factor authentication

+ At Tier 2 and higher, two factor authentication is required to access the Environment.
