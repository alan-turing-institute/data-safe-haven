Sensitive Data Handling at the Turing - Overview for Data Providers
===================================================================

Introduction
------------

Secure environments for analysis of sensitive datasets are essential for research.

Such "data safe havens" are a vital part of the research infrastructure.

It is essential that sensitive or confidential datasets are kept secure, both to enable analysis of 
personal data in a manner that is capable of being compliant with data protection law, 
and to preserve the social license to carry out research activities.

To create and operate these environments safely, efficiently, and ensure usability, requires, as with many sociotechnical systems, a complex stack of interacting 
business process and design choices. This document describes the approaches taken by the Alan Turing Institute when building and managing environments for productive, secure, collaborative research projects.

We propose choices for the security controls that should be applied in the areas of:

* data classification
* data reclassification 
* data ingress
* data egress
* software ingress
* user access
* user device management
* analysis environments

We do this for each of a small set of security "Tiers" - noting that the choice of security controls depends on the sensitivity of the data.

This document describes our approach to handling research data. It does not cover the Turing's core enterprise information security practices, which are described elsewhere. Nor do we cover the data-centre level or organisational management security practices which are fundamental to any secure computing facility - we do not operate our own data centres, but rely on upstream ISO 270001 compliant data centre provision, such as Microsoft Azure and the Edinburgh Parallel Computing Centre.

Software-defined infrastructure
-------------------------------

Our approach - separately instantiating an isolated environment for each project - would involve a hugely
inefficient duplication of effort were it not for the advent of "software defined infrastructure".

It is now possible to specify a whole arrangement of IT infrastructure, servers, storage, access policies and so on,
completely as **code**. This code is executed against web services provided by infrastructure providers (the APIs
of cloud providers such as Microsoft, Amazon or Google, or an in-house "private cloud" using a technology such
as OpenStack), and the infrastructure instantiated.

Our model therefore assumes the availability of a software defined infrastructure provision offering, in an ISO27001
compliant data-centre and organisation, the scripted instantiation of virtual machines, storage,
and secure virtual networks. 

We also assume that "Identification, Authorisation and Authentication" (IAA) is available as a service
from this provider, so that user account creation, the creation of security groups, 
the assignment of users to security groups, the restriction of access to resources by such users,
login challenge by password and a second factor, password reset, and so on, are all upstream services.

A software defined infrastructure platform, on which to build, means that the definition of the research environment can be meaningfully audited - 
as no aspect of it is not described formally in code, it can be fully scrutinised.

Secure data science
-------------------

We highlight two assumptions about the research user community critical to our design:

Firstly, we must consider not only accidental breach and deliberate attack, but also the possibility of "workaround breach", where
well-intentioned researchers, in an apparent attempt to make their scholarly processes easier, circumvent security measures, for example, by copying out datasets to their personal device.
Our user community are relatively technically able; the casual use of technically able circumvention measures, not by adversaries but by
colleagues, must be considered.
This can be mitigated by increasing awareness and placing inconvenience barriers in the way of undesired behaviours, even if those barriers are in principle not too hard to circumvent.

Secondly, research institutions need to be open about the research we carry out, and hence, the datasets we hold. This is because of both the need to 
publish our research as part of our impact cases to funders, and because of the need to maintain the trust of society, which provides our social licence. This means
we cannot rely on "security through obscurity": we must make our security decisions assuming that adversaries know what we have, what we are doing with it, and
how we secure it. 

Why classify?
-------------

One of the major drivers for usability or security problems is over- or under-classification, that is, treating data as more or less sensitive than it deserves.

Regulatory and commercial compliance requirements place constraints on the use of datasets; implementation of that compliance must be set in the context of the threat and risk profile and balanced with researcher productivity.

Almost all security measures can be circumvented, security can almost always be improved by adding additional barriers, and improvements
to security almost always carry a cost in usability and performance.

Misclassification is seriously costly for research organisations and their partners: overclassification results not just in lost researcher productivity, but also a loss of scientific engagement, as researchers choose not to take part in a project with cumbersome security requirements. Systematic overclassification **increases** data risk by encouraging workaround breach.

The risks of under-classification include not only
legal and financial sanction, but the loss of the social licence to operate of the whole community of data science researchers.

A model for secure data research projects
-----------------------------------------

### Environments and Projects 

Assessing the sensitivity of a dataset requires an understanding of the base sensitivity of the information contained in the dataset and of the impact on that base sensitivity of the operations that it will undergo in the research project. 
The classification exercise therefore relates to each stage of a project and not simply to the datasets as they are introduced into it.

Classification to a tier is therefore a property of an Environment: the project, a subset of its tasks, and a collection of datasets. It is not a property of a dataset, because a particular dataset's sensitivity depends on the data it can be combined with, and the use to which it is put.

A project will create one or more secure research environments corresponding to the stages of the project, and the current tasks in operation.

### Researcher

A project member, who analyses data to produce results. We reserve the capitalised term "Researcher" for this role
in our user model. We use the lower case term when considering the population of researchers more widely.

### Investigator

The research project lead, this individual is responsible for ensuring that the project staff comply with
the Environment's security policies. A single lead investigator must be responsible for a project. Multiple collaborating institutions may have
their own lead academic staff, and academic staff might delegate to a researcher the leadership as far as interaction with the secure environment is concerned.
In both cases, the term Investigator here is independent of this - regardless of academic status or institutional collaboration, this individual accepts responsibility for the conduct of the project and its members.

### Referee

A Referee volunteers to review code or derived data, providing evidence to the Investigator and Dataset Provider Representative that the researchers are complying with data handling practices. 

### Dataset Provider and Representative

The **Dataset Provider** is the organisation who provided the dataset under analysis. The Dataset Provider will designate a single representative contact to liaise with the Turing.
This individual is the **Dataset Provider Representative**.
They are authorised to act on behalf of the Dataset Provider with respect to the dataset and must be in a position to certify that the Dataset Provider is authorised  to share the dataset with the Turing.

There may be additional people at the Dataset Provider who will have input in discussions around data sharing and data classification.
It is the duty of the Dataset Provider Representative to manage this set of stakeholders at the Dataset Provider.

### Research Manager

A designated staff member in the Turing who is responsible for creation and monitoring of projects and environments.
This should be a member of professional staff with oversight for data handling in one or more research domains.

### System Manager 

Members of Turing staff responsible for configuration and maintenance of the secure research environment.

Environment Tiers
-----------------

Our approach for secure information processing tiers is not new: they correspond to UK government classifications, and reconcile these to the definitions of personal data, whether or not something is 'special category' under the GDPR, and relate these to common activities in the research community.

In this paper, by 'sensitive datasets' we mean datasets with confidentiality restrictions and/or those which are subject to data protection law (DPL).

We emphasise that this classification is based on considering the sensitivity of all information handled in the project, including information that may be generated by
combining or processing input datasets. In every case, the categorisation does not depend only on the input datasets, but on combining information
with other information or generated results.

Derived information may be of higher security tier than the information in the input datasets.
(For example, information on the identities of those who are suspected to possess an undiagnosed neurological condition on the basis of analysis of public social media data.) Where a project team believes this will be the case, the datasets should be transferred to the higher tier of secure environment before the project commences.

If it becomes apparent during the project that intended analysis will produce this effect then the datasets should be transferred to the relevant higher security tier environment before that analysis is carried out.

In the below, "personal data" follows the GDPR definition: information linked to living individuals. It excludes information about individuals who
are dead.

### Tier 0

Tier 0 environments are used to handle publicly available, open information, where all generated and combined
information is also suitable for open handling.

Tier 0 applies where none of the information
processed, combined or generated includes personal data.

Although this data is open, there are still advantages to handling it through a managed data analysis infrastructure. 

Management of Tier 0 data in a visible, well ordered infrastructure provides confidence to stakeholders as to the handling of more sensitive datasets. 

Although analysis may take place on personal devices or in non-managed cloud-based analysis environments, the data should still therefore be listed through the inventory and curatorial systems of a managed research data environment.

Finally, audit trails as to the handling of Tier 0 information mitigate the risk attendant on misclassification.

### Tier 1

Tier 1 environments are used to handle, process and generate
data that is intended for eventual publication or that could be published without reputational damage. 

Information is kept private in order to give the research team a competitive advantage, not due to legal data protection requirements.

Both the information and the proposed processing must otherwise meet the criteria for Tier 0.

It may be used for pseudonymised or synthetic information generated from personal data, where one has absolute 
confidence in the quality of pseudonymisation. This makes the information no longer personal data. 
The risk of processing it so that individuals are capable of being re-identified must be considered as part of the classification process.

### Tier 2

Tier 2 environments are used to handle, combine or generate information which is not linked to living individuals.

It may be used for pseudonymised or synthetic information generated from personal data, where we have strong, but not absolute,
confidence in the quality of pseudonymisation. This makes the information no longer personal data, but the risk of processing it so that individuals are capable of being re-identified must be considered as part of the classification process.

The pseudonymisation process itself, if carried out in the Turing, should take place in a Tier 3 environment.

A typical model for a project will be to instantiate both Tier 2 and Tier 3 environments, with pseudonymised or synthetic data generated in 
the Tier 3 environment and then transferred to the Tier 2 environment.

Tier 2 environments are also used to handle, combine or generate information which is confidential, but not, in commercial or national security terms, sensitive.
Tier 2 corresponds to the government OFFICIAL classification.
This includes commercial-in-confidence datasets or intellectual property where the consequences of legal or financial consequences from disclosure are low.

At Tier 2 and above, reclassification of the results of the project for publication must be run following a careful process. Derived information must otherwise be maintained as confidential.

At Tier 2, the most significant risks are "workaround breach" and the risk of  mistakenly believing data is robustly
pseudonymised, when in fact re-identification might be possible.

### Tier 3

Tier 3 environments are used to handle, combine or generate personal data, excluding personal data where there is a risk that disclosure might pose a substantial threat to the personal safety, health or security of the data subjects (which would be Tier 4).

This also includes pseudonymised or synthetic information generated from personal data, where we have only weak
confidence in the quality of pseudonymisation.

Tier 3 environments are also used to handle, combine or generate information, including intellectual property, which is sensitive in commercial or national 
security terms. 
This tier anticipates the need to defend against compromise by attackers with bounded capabilities and resources.
This may include hacktivists, single-issue pressure groups, investigative journalists, competent individual hackers and the majority of criminal individuals and groups.
The threat profile excludes sophisticated, well-resourced and determined threat actors, such as highly capable serious organised crime groups and state actors.
This corresponds to the governmental ‘OFFICIAL–SENSITIVE’ categorisation. 

The difference between Tier 2 and Tier 3 environments is the most significant in this model, as it carries the highest consequences, both for researcher productivity and organisational risk. 

At Tier 3, the risk of hostile actors attempting to break into the secure environment becomes significant.

### Tier 4

Tier 4 environments are used to handle, combine or generate personal data 
where disclosure poses a substantial threat to the personal safety, health or security of the data subjects.

This also includes handling, combining or generating datasets which are sensitive in commercial or national 
security terms, and are likely to be subject to attack by sophisticated, 
well-resourced and determined actors, such as serious organised crime groups and state actors. This
corresponds to the UK government "SECRET" categorisation.

It is at Tier 4 that the risk of hostile actors penetrating the project team becomes significant.

Connections to the secure environment
-------------------------------------

A remote desktop connection, allowing access to GUI applications should be provided
to allow researchers to connect to the remote secure analysis environment.
This requires two-factor authentication, with, at some tiers, the copy paste function disabled.

At some tiers, we may provide **secure shell** connections in addition to the remote desktop.

Such text-based access is sufficient for some professional data scientists, with the provenance
information provided by command-driven data analysis a primary driver for this preference. (Processes can 
easily be reproduced based on the commands typed.) 
When not needed, providing a remote desktop interface adds complexity and therefore risk.

At every tier, long passphrases
should be enforced, and users are trained in the use of keychain managers on their access devices, locked with two-factor authentication, so that the inconvenience of repeatedly
typing a long passphrase is mitigated, reducing the risk of users choosing insecure passwords.

At some tiers, specific commands commonly used for data copy-out, are blocked for users. 

In neither case is copy-out to the machine used to access the environment absolutely prevented - with remote desktop software, malicious users can script automated screen-grabs. However, this can be made difficult in order to deter casual workaround risk, and, at the highest tiers, prevented by only permitting access to the environment from machines permanently located within a secure physical environment.

The Classification Process
--------------------------

The Dataset Provider Representative and Investigator must agree on a data classification.

An initial classification should be made by the Dataset Provider Representative and an appropriate environment instantiated, so that
ingress can occur and the remainder of the review can take place. 

This may take some time while the investigator and research manager familiarise
themselves with the data, so the environment should make record of this preliminary phase. 
If necessary, following this phase, the team should then reclassify once they have seen the data in the higher tier, following the reclassification process defined below.

User lifecycle
---------------

Users who wish to have access to the secure environment should set their credentials within the Turing secure environment management system.

Projects are created in the management system by a Research Manager, and an Investigator assigned.

Research Managers and Investigators may add users to groups corresponding to specific research projects
through the management framework.

The Research Manager has the authority to assign Referees and Data Provider Representatives to a project.

At some tiers, new members of the research team or Referees must also be approved by the Dataset Provider Representative.

Before joining a project, Researchers, Investigators and Referees must certify in the management system that they have received training in handling data in the system.

In line with statute, the Dataset Provider Representative must also certify that the organisation providing the dataset has permission from the dataset owner, 
if they are not the dataset owner, to share it with the Turing, and this should be recorded within the management system database.

Data ingress
------------

How do sensitive datasets arrive in the Secure Data Volume?

The policies defined here minimise the number of people who have access to restricted information before it is in the secure research environment.

Datasets must only be transferred from the Dataset Provider to the research environment after an initial classification has been completed
and the data sharing agreement executed.

The transfer process should be initiated by the Research Manager in the management framework, opening a new empty secure data volume for deposit.

Once made available, all transfer must use encrypted channels, (SCP or SSL).  No dataset should be sent over email, 
via dropbox, google drive, sharepoint or office 365 groups. Data upload should always be directly into the secure volume
to avoid the risk of individuals unintentionally retaining the dataset for longer than intended.

The Dataset Provider Representative should then immediately indicate the transfer is complete. In doing so, they lose access to the data volume. 

The Research Manager should authorise the mounting of the data volume in the analysis environment, using the web interface.

While open for deposit, this volume provides an additional risk of a third party accessing the dataset. We define two tiers of 
protection against this risk:

### High security transfer protocol

This protocol should limit all aspects of the transfer to provide the minimum necessary exposure:

* The time window during which dataset can be transferred
* The networks from which it can be transferred

To deposit the dataset, a time limited or one-time access token, providing write-only access to the secure transfer volume, will be generated and transferred via a secure channel to the Dataset Provider Representative.

Software library distributions
------------------------------

Maintainers of shared research computing environments face a difficult challenge in keeping research algorithm libraries and platforms
up to date - and in many cases these conflict. The use of single-project virtual environments opens another possibility: downloading the software as needed for the project
from package managers such as the Python package index. To achieve this in a secure environment, without access to the
external internet, requires maintenance of mirrors of package repositories inside the environment. 

Use of package mirrors inside the environment means that the set of default installed packages can be kept
to a minimum, reducing the likelihood of encountering package-conflict problems and saving on
System Manager time.

At some tiers, however, not all software in the public repositories are immediately mirrored.
Malicious software has occasionally been able to become an official download on official package mirrors. 
This is a low risk, since the environment will not have access to the internet, but must still be guarded against at the higher tiers.

At some tiers we mirror only whitelisted packages, at others we mirror the full package list but with a delay
(during which the community will catch most malicious code on package mirrors.)

Storage
-------

What storage volumes exist in the analysis environment?

A Secure Data volume is a read-only volume that contains the secure data for use in analyses. It is mounted read-only
in the analysis environments that must access it. One or more such volumes will be mounted depending on how many managed secure datasets the environment has access to.

A Secure Document volume contains electronically signed copies of agreements between the Data Provider and the Turing.

A Secure Scratch volume is a read-write volume used for data analysis. Its contents are automatically and regularly deleted.

An Output volume is a read-write area intended for the extraction of results, such as figures for publication. 

The Software volume is a read-only area which contains software used for analysis. 

A Home volume is a smaller read-write volume used for local programming and configuration files. It should not be used for data analysis outputs, though this is enforced only in policy, not technically. Configuration files for software in the software volume point to the Home volume.

User Devices
------------

What devices should researchers use to connect to the secure research environment?

We define two types of devices: 

* Managed devices
* Open devices

### Managed devices

Managed devices do not have administrator/root access.

They have an extensive suite of research software installed.

This includes the ability to install packages for standard programming environments without the need for administrator access.

Researchers can compile and run executables they code in User Space.

### Open Devices

Staff researchers and students should be able to choose that an employer-supplied device should instead have an administrator/root account to which they do have access.

These devices are needed by researchers who work on a variety of bare-metal programming tasks.

However, such devices are not able to access higher tier secure environments.

User device networks
--------------------

Our network security model distinguishes three dedicated research networks for
user devices.

* The open internet
* An Institutional network
* A Restricted network

An Institutional network corresponds to organisational guest network access (such as Eduroam). Access to environments can be restricted to machines on an Instituitional network, but it is assumed the whole research community can access this network, though this access may be remote for authorised users (for example, via VPN).

A Restricted network may be linked between multiple institutions (such as partner research institutions), so that researchers travelling to collaborators' sites will be able to connect to Restricted networks, and thus to secure environments, while away from their home institution.

Remote access to a Restricted network (e.g. via VPN) should not be possible.

Firewall rules for the environments enforce restricted network IP ranges corresponding to these networks.

Of course, secure environments themselves should, at some tiers, be restricted from accessing anything outside an isolated network for that secure research environment.

Physical security
-----------------

Some data requires a physical security layer around not just the data centre,
but the physical environment users use to connect to it.

We distinguish three levels of physical security for research spaces:

* Open research spaces
* Medium security research spaces
* High security research spaces

Open research spaces include university libraries, cafes and common rooms.

Medium security research spaces control the possibility of unauthorised viewing.
Card access restricting entry to employees is required. 
Screen adaptations or desk partitions can be adopted in open plan research environments, if there is a high risk of "visual eavesdropping".

Secure research spaces control the possibility of the researcher deliberately
removing data. Devices will be locked to appropriate desks, and neither enter nor leave 
the space. Mobile devices should be removed before entering, to block the 'photographic hole',
where mobile phones are used to capture secure data from a screen.

Firewall rules for the environments must enforce restricted network IP ranges corresponding to these 
research spaces.

Data reclassification
---------------------

From a project, datasets can often be created which merit use in an environment with a lower classification.

For example, data may be pseudonymised, bringing it from Tier 3 to Tier 2, or used to build into a trained model, which might become Tier 1, or aggregated into a summary statistic, and published as Tier 0.

However, the assertion that a derived data artefact indeed merits a lower tier cannot be made without challenge:
understanding the possibility of personal data leaking through generated pseudonymised, synthetic or other derived datasets 
is a delicate endeavour.

Pseudonymised datasets can, on linking to another published dataset, become identifiable.

We therefore require the reclassification process to certify an authors' claims about the script which was used to produce the derived data artefact,
and that identifiable data is not released.

No reclassification should be permitted without a script describing, in code, the process used to create the derived dataset. 
(The authors do not believe that a spreadsheet can be properly audited for this.)

A reclassification script should be written by a project member. This is placed on the software volume or home volume, and run so that the derived
dataset is placed on the Output Volume.

Following review by the data provider representative, investigator, or an independent referee (depending on tier) of the reclassification script and generated derived dataset, a new environment can be created with the former egress volume now mounted as a new secure data volume within a new environment, at a different tier. The existence of this environment as a "derived environment" should be noted, with the originating environment's ID and the reclassification script preserved.

Software Ingress
----------------

Package mirrors allow ingress of standard software.

But since we forbid copy-paste, how should researcher-written software, written outside the secure
environment, arrive inside?

If we allow access to the internet to `git clone` such software, this might allow for data to leave the environment, and at higher tiers, there is no access to the open internet. 

Instead, for researcher-written code developed elsewhere, we implement a **one-way airlock policy**:

For software that does not require admin rights to install, software is ingressed in a similar manner as data, via a software ingress volume:

In **external mode** the researcher is provided temporary **write-only** access to a software ingress volume.

Once the researcher transfers the software source or installation package to this volume, their access is revoked and the software is subject to a level of review appropriate to the environment tier.

Once any required review has been passed, the software ingress volume is switched to **internal mode**, where it is made available to researchers within the analysis environment with **read-only** access and they can then install the software or transfer the source to a version control repository within the secure environment as appropriate.

For software that requires admin rights to install:

In **install mode**, a virtual machine is created outside of the secure environment. The user has administrator privileges on the machine and can install any software necessary from the open internet. There is no access to the secure data during this process.

In **analysis mode**, the VM image is moved into the secure environment where internet access is disabled. 

The process to switch volumes between these modes should be managed through a process in the web-based management software.

The choices
------------

Having described the full model, processes, and lifecycles, we can now enumerate the list of choices that
can be made for each Environment. These are all separately configurable on an environment-by-environment basis. However, we recommend the following at each tier.

### Package mirrors

At Tier 3 and higher, package mirrors should include only white-listed software.

At Tier 2, package mirrors should include all software, one month behind the reference package server.
Critical security updates should be fast-tracked.

At Tier 1 and 0, installation should be from the reference package server on the external internet.

### Inbound network

Only the Restricted network will be able to access Tier 3 and above, and only via the access node.

Tier 2 environments should only be accessible from an Institutional network.

Tier 1 and 0 environments should be accessible from the Internet.

### Outbound network

At Tier 1 and 0 the internet is accessible from inside the research environment,
at all other tiers the virtual network inside the environment is completely isolated.

### User devices

Open devices should not be able to access the Restricted network.

Managed laptop devices should be able to leave the physical office where the Restricted network exists, but should have no access to Tier 3 or above environments while 'roaming'.

### Physical security

Tier 2 and below environments should not be subject to physical security.

Tier 3 access should be from the medium security space.

Tier 4 access must be from the high security space.

### User management

At Tier 2 and below, the Investigator has the authority to add new members to the research team, and the research manager has the authority to assign Referees.

At Tier 3 and above, new Referees or members of the research team must be counter-approved by the Dataset Provider Representative.

### Connection

At Tier 1 and Tier 0, ssh access to the environment is possible without restrictions. The user should be able to set-up port forwarding (ssh tunnel) and use this to access remotely-running UI clients via a native client browser.

At Tier 3, only remote desktop access is enabled.

At Tier 2, we are unsure at this stage if our objective to enable restricted SSH access to this
tier is possible. In the interim, only remote desktop access is enabled.

### Internet access

Tier 2 and above environments have no access to the internet, other than inbound through the 
access connection

Tier 0 and Tier 1 environments have access to the internet.

### Software ingress

For Tier 3, additional software or virtual machines arriving through the software ingress process
must be reviewed an signed off by the Investigator and Referee before it can be accessed inside 
the environment (with the exception of pre-approved virtual machines or package mirrors).

For Tier 2, additional software or virtual machines requested by Researchers do not require 
review anord sign off by anyone else, but must arrive through the software ingress process.

For Tier 0 and Tier 1, users should be able to install software directly into the environment 
(in user space) from the open internet.

### Data ingress

For Tier 3 and above, the high-security data transfer process is required.
Lower-security data transfer processes are allowed at Tier 2 and below.

### Copy-paste

At Tier 1 and 0 copy-out should be permitted where a user believes their local device is secure, with the permission of the investigator.

At Tier 2, copy-paste out of the secure research environment must be forbidden by policy, but not enforced by configuration, unlike in Tier 3. Users must have to confirm they understand and accept the policy on signup using the web management framework.

At Tiers 3 and 4, copy-paste is disabled on the remote desktop.

### Refereeing of classification

Independent referee scrutiny of data classification is required when the initial classification
by the Investigator and Data Provider Representative is Tier 2 or higher.

### Refereeing of reclassification

Independent referee scrutiny of data reclassification to a lower tier is required when the 
environment in which the derived data is generated is Tier 3 or higher.

### Data egress

At Tier 3 and higher, Data Provider Representative signoff of all egress of data or code from the secure
environment is required.
