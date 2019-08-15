Sensitive Data Handling at the Turing - Overview for Data Providers
===================================================================

Introduction
------------

Secure Environments for analysis of sensitive datasets are essential for research.

Such "data safe havens" are a vital part of the research infrastructure.

It is essential that sensitive or confidential datasets are kept secure, both to enable analysis of personal data in a manner that is capable of being compliant with data protection law, and to avoid jeopardising the consent of society for research activities with personal data (called 'social license').

To create and operate these Environments safely and efficiently whilst ensuring usability, requires, as with many sociotechnical systems, a complex stack of interacting business process and design choices. This document describes the approaches taken by the Alan Turing Institute when building and managing Environments for productive, secure, collaborative research projects.

We propose choices for the security controls that should be applied in the areas of:
* data classification
* data ingress (data entering a secure Environment from an external source)
* data egress (data leaving a secure Environment to an external recipient)
* software ingress (software entering a secure Environment from an external source)
* user access
* user device management
* analysis Environments

We do this for each of a small set of security "Tiers" - noting that the choice of security controls depends on the sensitivity of the data.

Why classify?
-------------

One of the major drivers for usability or security problems is over- or under-classification, that is, treating data as more or less sensitive than it deserves.

Regulatory and commercial compliance requirements place constraints on the use of datasets; implementation of that compliance must be set in the context of the threat and risk profile and balanced with researcher productivity.

Almost all security measures can be circumvented, security can almost always be improved by adding additional barriers, and improvements to security almost always carry a cost in usability and performance.

Misclassification is seriously costly for research organisations and their partners: overclassification results not just in lost researcher productivity, but also a loss of scientific engagement, as researchers choose not to take part in a project with cumbersome security requirements. Systematic overclassification increases data risk by encouraging workaround breach.

The risks of under-classification include not only legal and financial sanction, but the loss of the social licence to operate of the whole community of data science researchers.

Document structure
----------------

This document describes our approach to handling research data. It does not cover the Turing's core enterprise information security practices, which are described elsewhere. Nor do we cover the data-centre level or organisational management security practices which are fundamental to any secure computing facility - we do not operate our own data centres, but rely on upstream data centre provision, such as Microsoft Azure and the Edinburgh Parallel Computing Centre, compliant with ISO 27001 (Information Security Management System Requirements).

The document is structured as follows: we begin by defining terms which are used throughout the document. We then discuss some aspects of the design, before describing our 'model' for secure research Environments. Next, we discuss the possible choices for each security control around each of the areas bullet-pointed above, while leaving open the question of which controls are appropriate at which tiers. Finally, we make specific choices assigning controls to security tiers.

Definitions - a model for secure data research projects
-----------------------------------------

### Work Packages

Assessing the sensitivity of a dataset requires an understanding of both the base sensitivity of the information contained in the dataset and of the impact on that base sensitivity of the operations that it will undergo in the research project. The classification exercise therefore relates to each stage of a project and not simply to the datasets as they are introduced into it.

Classification to a tier is therefore **not** a property of a dataset, because a dataset's sensitivity depends on the data it can be combined with, and the use to which it is put.

In our model, projects are divided into **work packages**, which we use here to refer to the activities carried out within a distinct phase of work carried out as part of a project, with a specific outcome in mind. A work package can make use of one or more datasets, and includes an idea of the analysis which the research team intends to carry out, the potential outputs they are expecting, and the tools they intend to use – all important factors affecting the data sensitivity.

Classification is carried out on work packages rather than individual datasets.

### Environments and Platforms

Once a work package has been classified, an appropriate secure analysis Environment is instantiated depending on the tier assigned.

For the initial work package in a project, a new Environment must always be deployed. For additional work packages, the project may deploy a new environment per work package or, where appropriate, add the new work package to an existing Environment deployed for the project.

When considering adding a work package to an existing environment, the **combination** of the new work package plus all existing work packages the Environment has already been used for must be considered as the effective work package when making classification decisions.
The classification tier of a combination of work package(s) can never be lower than the highest classification tier of any of the individual work packages, but may be higher due to additional risks introduced by combining datasets and activities across work packages.
If the combined classification is higher than the tier associated with the existing Environment, a new Environment must be deployed.
The classification tier of an Environment cannot be upgraded or downgraded "in place". 

Depending on the classification assigned, an Environment may be instantiated on one of several supported Platforms. The Turing currently supports secure deployments to Microsoft's Azure cloud platform and to its own dedicated secure compute cluster.

### Researcher

A project member, who analyses data to produce results. We reserve the capitalised term "Researcher" for this role in our user model. We use the lower case term when considering the population of researchers more widely.

### Investigator

The research project lead, this individual is responsible for ensuring that project staff comply with the Environment's security policies. A single lead Investigator must be responsible for a project. Multiple collaborating institutions may have their own lead academic staff, and academic staff might delegate to a researcher the leadership as far as interaction with the Environment is concerned. In both cases, the term Investigator here is independent of this - regardless of academic status or institutional collaboration, this individual accepts responsibility for the conduct of the project and its members.

### Referee

A Referee volunteers to review code or derived data (data which is computed from the original dataset), providing evidence to the Investigator and Dataset Provider Representative that the researchers are complying with data handling practices.
Referees also play a role in classifying work packages at Tiers 2 or above, when they should be consulted by either the research team or the Dataset Provider Representative (see below).

### Dataset Provider and Representative

The **Dataset Provider** is the organisation who provided the dataset under analysis. The Dataset Provider will designate a single representative contact to liaise with the Turing. This individual is the **Dataset Provider Representative**. They are authorised to act on behalf of the Dataset Provider with respect to the dataset and must be in a position to certify that the Dataset Provider is authorised to share the dataset with the Turing.

There may be additional people at the Dataset Provider who will have input in discussions around data sharing and data classification. It is the duty of the Dataset Provider Representative to manage this set of stakeholders at the Dataset Provider.

### Programme Manager

A designated staff member in the research institution who is responsible for creating and monitoring projects and Environments and overseeing a portfolio of projects. This should be a member of professional staff with oversight for data handling in one or more research domains.

The Programme Manager can add new users to the system and assign users to specific projects. They assign Project Managers and can, if they wish, take on this role themselves.

### Project Manager

A staff member with responsibility for running a particular project. This role could be filled by the Programme Manager, or a different nominated member of staff within the research institution.

While the Programme Manager should maintain responsibility for adding users to the user list, and can add users to projects, the Project Manager should also have the authority to assign existing users to their project. To do this they will need to be able to review and search existing users.

### System Manager 

Members of Turing staff responsible for configuration and maintenance of the Environment.

Software-defined infrastructure
-------------------------------

Our approach - separately instantiating an isolated Environment for each project - is made feasible by the advent of "software-defined infrastructure".

It is now possible to specify a whole arrangement of IT infrastructure, servers, storage, access policies and so on, completely as **code**. This code is executed against web services provided by infrastructure providers (the APIs of cloud providers such as Microsoft, Amazon or Google, or an in-house "private cloud" using a technology such as OpenStack), and the infrastructure instantiated.

Our model therefore assumes the availability of a software-defined infrastructure provision offering, in an ISO 27001 compliant data-centre and organisation, the scripted instantiation of virtual machines, storage, and secure virtual networks.

We also assume that "Identification, Authorisation and Authentication" (IAA) is available as a service from this provider, so that they provide user account creation, the creation of security groups, the assignment of users to security groups, the restriction of access to resources by such users, login challenge by password and a second factor, password reset, and other such security considerations.

A software-defined infrastructure platform on which to build, means that the definition of the Environment can be meaningfully audited - as no aspect of it is not described formally in code, it can be fully scrutinised.

Secure data science
-------------------

We highlight two assumptions about the research user community critical to our design:

Firstly, we must consider not only accidental breach and deliberate attack, but also the possibility of "workaround breach", where well-intentioned researchers, in an apparent attempt to make their scholarly processes easier, circumvent security measures, for example, by copying out datasets to their personal device. Our user community are relatively technically able; the casual use of technically able circumvention measures, not by adversaries but by colleagues, must be considered. This can be mitigated by increasing awareness and placing inconvenience barriers in the way of undesired behaviours, even if those barriers are in principle not too hard to circumvent.

Secondly, research institutions need to be open about the research we carry out, and hence, the datasets we hold. This is because of both the need to publish our research as part of our impact cases to funders, and because of the need to maintain the trust of society, which provides our social licence. This means we cannot rely on "security through obscurity": we must make our security decisions assuming that adversaries know what we have, what we are doing with it, and how we secure it.

Environment Tiers
-----------------

Our recommendation for secure information processing tiers is based on work which has gone before. We have begun with the UK government classifications, and reconciled these to the definitions of personal data, whether or not something is 'special category' under the GDPR or relates to criminal convictions, and related them to common activities in the research community.

Where input datasets contain personal data, consideration should always be given at the outset to minimising the personal data, including by pseudonymisation or anonymisation.

**Pseudonymised data** is still personal data, as it can be re-identified by those who hold the key to turn pseudonyms back into individual identifiers. This includes synthetic data derived from personal data, or models trained on personal data.

**Anonymised data**, including pseudonymised data where that key is destroyed, is not personal data when it is impossible to re-identify any living individuals from it. However, if the quality of anonymisation is ambiguous or if individuals can be identified when the anonymised data is combined with another dataset, such data would by definition not be anonymised, and would therefore bee personal data. The question as to whether re-identification is possible or not is a very subtle one, and the assessment of this risk is critical to the assignment of security tiers.

We emphasise that this classification is based on considering the sensitivity of all information handled in the project, including information that may be generated by combining or processing input datasets. In every case, the categorisation does not depend only on the input datasets, but on combining information with other information or generated results in a work package.

Derived information may be of higher security tier than the information in the input datasets. (For example, information on the identities of those who are suspected to possess an undiagnosed neurological condition on the basis of analysis of public social media data.) This should form part of the information constituting a work package; when a project team believes this will be the case, the work package should be classified at the higher tier of secure Environment.

If it becomes apparent during the project that intended analysis will produce this effect then the inputs should be treated as a new work package with this extra information, and classified afresh, following the full classification process below.
In the below, "personal data" follows the GDPR definition: information from which a living individual is identified or identifiable. It excludes information about individuals who are dead.


### Tier 0

Tier 0 Environments are used to handle publicly available, open information, where all generated and combined information is also suitable for open handling.

Tier 0 applies where none of the information processed, combined or generated includes personal data, commercially sensitive data, or data which will have legal, political or reputational consequences in the event of unauthorised disclosure.

Tier 0 data should be considered ready for publication. Although this data is open, there are still advantages to handling it through a managed data analysis infrastructure.

Management of Tier 0 data in a visible, well ordered infrastructure provides confidence to stakeholders as to the handling of more sensitive datasets.

Although analysis may take place on personal devices or in non-managed cloud-based analysis Environments, the data should still therefore be listed through the inventory and curatorial systems of a managed research data Environment.

Finally, audit trails as to the handling of Tier 0 information reduce risks associated with misclassification - if data is mistakenly classified as a lower tier than it should be, we still retain information as to how it was processed during the period of misclassification.

### Tier 1

Tier 1 Environments are used to handle, process and generate data that is intended for eventual publication or that could be published without reputational damage.

Information is kept private in order to give the research team a competitive advantage, not due to legal data protection requirements.

Both the datasets and the proposed processing must otherwise meet the criteria for Tier 0.

It may be used for pseudonymised or synthetic information generated from personal data, where one has absolute confidence in the quality of pseudonymisation. This makes the information no longer personal data. This does not include pseudonymised data which can be re-identified in combination with a key or other dataset.

It may also be used for commercial data where commercial consequences of disclosure would be no impact or very low impact, with the agreement of all parties.

### Tier 2

Tier 2 Environments are used to handle, combine or generate information which is not linked to personal data.

It may be used for pseudonymised or synthetic information generated from personal data, where we have strong, but not absolute, confidence in the quality of pseudonymisation. The risk of processing it so that individuals are capable of being re-identified must be considered as part of the classification process.

The pseudonymisation or anonymisation process itself, if carried out in the Turing, should take place in a Tier 3 Environment.

A typical model for a project will be to instantiate both Tier 2 and Tier 3 Environments, with pseudonymised or synthetic data generated in the Tier 3 Environment and then transferred to the Tier 2 Environment.

Tier 2 Environments are also used to handle, combine or generate information which is confidential, but not, in commercial or national security terms, sensitive. This includes commercial-in-confidence datasets or intellectual property where the legal, commercial, political and reputational consequences from disclosure are low. Where such consequences are not low, Tier 3 should be used.

At Tier 2, the most significant risks are "workaround breach" and the risk of mistakenly believing data is robustly pseudonymised, when in fact re-identification might be possible.

Tier 2 corresponds to the government OFFICIAL classification.

### Tier 3

Tier 3 Environments are used to handle, combine or generate personal data, excluding personal data where there is a risk that disclosure might pose a substantial threat to the personal safety, health or security of the data subjects (which would be Tier 4).

This also includes pseudonymised or synthetic information generated from personal data, where we have only weak confidence in the quality of pseudonymisation.

Tier 3 Environments are also used to handle, combine or generate information, including intellectual property, which is sensitive in commercial, legal, political, or national security terms. This tier anticipates the need to defend against compromise by attackers with bounded capabilities and resources. This may include hacktivists, single-issue pressure groups, investigative journalists, competent individual hackers and the majority of criminal individuals and groups. The threat profile excludes sophisticated, well-resourced and determined threat actors, such as highly capable serious organised crime groups and state actors. This tier corresponds to the governmental ‘OFFICIAL–SENSITIVE’ categorisation.

The difference between Tier 2 and Tier 3 Environments is the most significant in this model, both for researcher productivity and organisational risk.

At Tier 3, the risk of hostile actors attempting to break into the Environment becomes significant.

### Tier 4

Tier 4 Environments are used to handle, combine or generate personal data where disclosure poses a substantial threat to the personal safety, health or security of the data subjects.

This also includes handling, combining or generating datasets which are sensitive in commercial or national security terms, and are likely to be subject to attack by sophisticated, well-resourced and determined actors, such as serious organised crime groups and state actors. This tier corresponds to the UK government "SECRET" categorisation.

It is at Tier 4 that the risk of hostile actors penetrating the project team becomes significant.

Connections to the Environment
-------------------------------------

A remote desktop connection allowing access to graphical interface applications should be provided to allow researchers to connect to the remote secure analysis Environment. At all but the lowest tiers, this requires two-factor authentication, and, at some tiers, the copy paste function is disabled.

At every tier, long and strong passphrases (for example, at least four randomly chosen dictionary words) should be enforced, and users are trained in the use of keychain managers on their access devices, locked with two-factor authentication, so that the inconvenience of repeatedly typing a long passphrase is mitigated, reducing the risk of users choosing insecure passwords.

At some tiers, we may provide **secure shell** connections using the command line, in addition to the remote desktop.

The text-based access this grants is sufficient for some professional data scientists. The primary driver for this preference is that processes can easily be reproduced based on the commands typed. If not needed, providing a remote desktop interface adds complexity and therefore risk.

At some tiers, specific commands commonly used for copying out data can therefore be blocked for users.

In neither case is the user absolutely prevented from copying out to the device used to access the Environment (with remote desktop software, malicious users can script automated screen-grabs). However, this can be made difficult in order to deter casual workaround risk, and, at the highest tiers, prevented by only permitting access to the Environment from user devices permanently located within a secure physical Environment.

We therefore believe it will be possible to make secure shell access just as secure as remote desktop access, but this remains a work in progress.

The classification process
--------------------------

The Dataset Provider Representative and Investigator must agree on an Environment classification for a work package. If the Environment is likely to be Tier 2 or higher, they should also involve an independent Referee.

Individual datasets should initially be ingressed into a Tier 3 Environment to which the Investigator has access, so that they can make a full classification based on complete information. The exception to this is when any party feels the data may be Tier 4, in which case the project should be reconsidered.

Once the Investigator has access to the full dataset, they go through the full classification process using the flowchart provided. The Dataset Provider Representative (and Referee if necessary) should go through this flowchart separately and come up with their own classification.

The project should only proceed if the Investigator, the Dataset Provider Representative, and the Referee if applicable, can come to a consensus for which tier the dataset should be classified at. 

If consensus cannot be reached, the Investigator should seriously reconsider whether to proceed with the project.

Once the work package has been classified by all parties, and a consensus reached, a new environment is instantiated at the appropriate tier, unless it has been classified at Tier 3, in which case analysis can begin in the existing environment.

If, at any point during the project, the research team decides to analyse the data differently or for a different purpose than previously agreed, this constitutes a new work package, and should be newly classified by repeating this process. This is also the case if the team wishes to ingress another dataset in combination, which will require Representatives from all Dataset Providers to arrive at the same consensus.

Data egress and new classification
----------------------------------------------------------------

The initial classification of a work package will often be for the purpose of ingress into an initial high-tier environment to carry out anonymisation, pseudonymisation or synthetic data generation work, with the intention of making the data appropriate for treatment in a lower-tier Environment.

It is a central premise of our model that any output data is classified as a new work package, separate from the work package that it is derived from.

This is the case whether the output data is for publication (which should only be from a Tier 1 or Tier 0 Environment) or will be analysed in a new Environment.

As a convenience, if derived data resulting from analysis is in a form which has been agreed with Dataset Provider Representatives at the initial classification stage – for example, a summary statistic which was the intended output for analysis of a sensitive dataset – then this re-classification may be pre-approved.

We recommend that, whenever data egress is conducted with the intent of establishing a new environment for further research, a Referee is consulted to ensure balance.

In all cases, classification of a work package at the point of egress should be done with all parties fully aware of the analytical processes which created the derived data from the initial work package – and these should be fully reproducible.

In most cases, this will necessitate an executable script describing, in code, the processes used. This script should be written by a project member placed on thee software volume or home volume, and run so that the derived dataset is placed on the Output Volume.

Data sharing agreement
----------------------------------------------------------------

Any contractual terms regarding the datasets should be added to the metadata for all datasets which have been classified, including any additional commitments to be made by Researchers on joining the project.

A template agreement with Dataset Providers normally used by the research institution (ideally, already existing) should be generated by the system before a dataset is ingressed to the initial Tier 3 environment. This should be a formal data sharing agreement as required under data protection law, and drafted with the benefit of legal advice.

After the full classification process is carried out, the agreement may need to be updated. We recommend that the wording of the initial agreement is such that it enables research at the tier anticipated by the Dataset Provider, or worded flexibly enough that changes after the initial classification are minimal.

The executed agreement itself, based on the templated, should be physically or digitally signed and stored within a secure document volume, with an index into it maintained within the database of the web management tool. A copy of the agreement should be automatically stored in the same location as the dataset for user reference when working with the data in the analysis Environment.

User lifecycle
---------------

Users who wish to have access to the Environment first complete an online form certifying they understand the confidentiality requirements. An account is then created for them within the Turing Environment management system, and the user activates this.

Projects are created in the management system by a Programme Manager, and an Investigator and Project Manager assigned.

Programme Managers and Project Managers may add users to groups corresponding to specific research projects through the management framework.

The Project Manager has the authority to assign Referees and Data Provider Representatives to a project.

At some tiers, new Referees or members of the research team must also be approved by the Dataset Provider Representative.

Before joining a project, Researchers, Investigators and Referees must certify in the management system that they have received training in handling data in the system.

As required by law, the Dataset Provider Representative must also certify that the organisation providing the dataset has permission from the dataset owner, if they are not the dataset owner themselves, to share it with the Turing, and this should be recorded within the management system database.

Data ingress (data entering a secure Environment from an external source)
----------------------------------------------------------------

The policies defined here minimise the number of people who have access to restricted information before it is in the Environment.

Datasets must only be transferred from the Dataset Provider to the Turing after an initial classification has been completed and the data sharing agreement executed.

The transfer process should be initiated by the Project Manager in the management framework, opening a new empty secure data volume for deposit. The Investigator should authorise the mounting of the data volume in the Tier 3 Environment, using th web interface.

After their dataset has been transferred, the Dataset Provider Representative should immediately indicate that the transfer is complete. In doing so, they lose access to the data volume.

Data should always be uploaded directly into the secure volume to avoid the risk of individuals unintentionally retaining the dataset for longer than intended.

While open for deposit, this volume provides an additional risk of a third party accessing the dataset. To deposit the dataset, a time-limited or one-time access token, providing write-only access to the secure transfer volume, is granted and transferrd via a secure channel to the Dataset Provider Representative.

When a work package is fully classified, data will either be ingressed from the initial Tier 3 Environment to a new Environment, or will stay in the original Tier 3 Environment, depending on sensitivity. The web management workflows should ensure that all parties have reached consensus on the classification tier at this stage before allowing analysis to begin.

Software library distributions
------------------------------

Maintainers of shared research computing Environments face a difficult challenge in keeping research algorithm libraries and platforms up to date - and in many cases these conflict. While sophisticated tools to help with this such as Spack exist, the use of single-project virtual Environments opens another possibility: downloading the software as needed for the project from package managers such as the Python package index, which automate the process of installing and configuring programs. To achieve this in a secure Environment, without access to the external internet, requires maintenance of mirrors (exact copies) of package repositories inside the Environment.

Use of package mirrors inside the Environment means that the set of default installed packages can be kept to a minimum, reducing the likelihood of encountering package-conflict problems (where a package can be prevented from being installed due to the presence of an existing package with the same name) and saving on System Manager time.

At Tiers 2 and above, however, not all software in the public repositories are immediately mirrored. Malicious software has occasionally been able to become an official download on official package mirrors. This is a low risk, since the Environment will not have access to the internet, but must still be guarded against at the higher tiers.

At Tiers 3 and above we mirror only a subset of whitelisted packages (packages which are explicitly marked as safe). At other tiers we mirror the full package list but with a delay, during which the wider international research community will catch most malicious code on package mirrors.

Storage
-------

Which storage volumes exist in the analysis Environment?

A Secure Data volume is a read-only volume that contains the secure data for use in analyses. It is mounted as read-only in the analysis Environments that must access it. One or more such volumes will be mounted depending on how many managed secure datasets the Environment has access to.

A Secure Document volume contains electronically signed copies of agreements between the Data Provider and the Turing.

A Secure Scratch volume is a read-write volume used for data analysis. Its contents are automatically and regularly deleted. Users can clean and transform the sensitive data with their analysis scripts, and store the transformed data here.

An Output volume is a read-write area intended for the extraction of results, such as figures for publication.

The Software volume is a read-only area which contains software used for analysis.

A Home volume is a smaller read-write volume used for local programming and configuration files. It should not be used for data analysis outputs, though this is enforced only in policy, not technically. Configuration files for software in the software volume point to the Home volume.

User Devices
------------

What devices should researchers use to connect to the Environment?

We define two types of devices: 

* Managed devices
* Open devices

### Managed devices

Managed devices do not have administrator/root access.

Managed devices could be provided by the Turing, or one of the partner research universities.

They have an extensive suite of research software installed.

This includes the ability to install packages for standard programming Environments without the need for administrator access.

Researchers can compile and run executables they code in User Space (the portion of system memory in which user processes run).

### Open Devices

Staff researchers and students should be able to choose that an employer-supplied device should instead have an administrator/root account to which they do have access.

These devices are needed by researchers who work on a variety of bare-metal programming tasks (programming directly to hardware without an operating system).

However, such devices are not able to access higher tier Environments.

They may include personal devices such as researcher-owned laptops.

User device networks
--------------------

Our network security model distinguishes three dedicated research networks for
user devices.

* The open internet (any network outside a research institution, such as in a researcher's home)
* An Institutional network
* A Restricted network

An Institutional network corresponds to organisational guest network access (such as Eduroam). Access to Environments can be restricted such that access is only allowed by devices which are connected to an Institutional network, but it is assumed that the whole research community can access this network, though this access may be remote for authorised users (for example, via VPN).

A Restricted network may be linked between multiple institutions (such as partner research institutions), so that researchers travelling to collaborators' sites will be able to connect to Restricted networks, and thus to secure Environments, while away from their home institution.

Remote access to a Restricted network (for example via VPN) should not be possible.

Firewall rules for the Environments enforce Restricted network IP ranges corresponding to these networks.

Of course, Environments themselves should, at some tiers, be restricted from accessing anything outside an isolated network for that Environment.

Physical security
-----------------

Some data requires a physical security layer around not just the data centre,
but the physical Environment users use to connect to it.

We distinguish three levels of physical security for research spaces:

* Open research spaces
* Medium security research spaces
* High security research spaces

Open research spaces include university libraries, cafes and common rooms.

Medium security research spaces control the possibility of unauthorised viewing. Card access or other means of restricting entry to only known researchers (such as the signing in of guests on a known list) is required. Screen adaptations or desk partitions can be adopted in open-plan Environments if there is a high risk of "visual eavesdropping".

Secure research spaces control the possibility of the researcher deliberately removing data. Devices will be locked to appropriate desks, and neither enter nor leave the space. Mobile devices should be removed before entering, to block the 'photographic hole', where mobile phones are used to capture secure data from a screen. Only researchers associated with a secure project have access to such a space.

Firewall rules for the Environments must enforce Restricted network IP ranges corresponding to these research spaces.

Software ingress (software entering a secure Environment from an external source)
------------------------------------------------------------------------------

Package mirrors allow ingress of standard software.

But since we disable copy-paste, how should researcher-written software, written outside the Environment, arrive inside?

If we allow access to the internet to git clone such software, this might allow for data to leave the Environment, and at higher tiers, there is no access to the open internet in any case.
Instead, for researcher-written code developed elsewhere, we implement a **one-way airlock policy**: installation is performed in an isolated environment without access to the data; after installations are completed, internet access must then be disabled and data access enabled.

For software that does not require admin rights to install, software is ingressed in a similar manner as data, using a software ingress volume:

In **external mode** the researcher is provided temporary **write-only** access to a software ingress volume.

Once the Researcher transfers the software source or installation package to this volume, their access is revoked and the software is subject to a level of review appropriate to the Environment tier.

Once any required review has been passed, the software ingress volume is switched to **internal mode**, where it is made available to Researchers within the analysis Environment with **read-only** access. They can then install the software or transfer the source to a version control repository within the Environment as appropriate.

For software that requires admin rights to install, the software installer is again brought in via a software ingress volume, but the installation process requires a System Manager to run the install process.

The choices
------------

Having described the full model, processes, and lifecycles, we can now enumerate the list of choices that
can be made for each Environment. These are all separately configurable on an environment-by-environment basis. However, we recommend the following at each tier.

### Package mirrors

At Tier 3 and above, package mirrors (copies of external repositories inside the secure Environment) should include only white-listed software.

At Tier 2, package mirrors should include all software, one month behind the server of the original package. Critical security updates should be fast-tracked.

At Tier 1 and 0, installation should be from the original package's server on the external internet.

### Inbound network

At Tier 2 and 3, the analysis machines themselves are not accessible directly. Instead, only a small group of user devices are exposed to the network, termed "access nodes". These provide the remote desktop facilities used indirectly to access the analysis Environments.

Only the Restricted network will be able to access "access nodes" for Tier 3 and above.

Tier 2 Environment access nodes should only be accessible from an Institutional network.

Tier 1 and 0 Environments should be accessible from the open internet.

### Outbound network

At Tier 1 and 0 the internet is accessible from inside the Environment. At all other tiers the virtual network inside the Environment is completely isolated.

### User devices

Open devices should not be able to access the Restricted network.

Managed laptop devices should be able to leave the physical office where the Restricted network exists, but should have no access to Tier 3 or above Environments while 'roaming'.

### Physical security

Tier 2 and below Environments should not be subject to physical security.

Tier 3 access should be from the medium security space.

Tier 4 access must be from the high security space (see above for definitions).

### User management

New user accounts are requested by users on the system and approved by Programme Managers before they're assigned to projects.

At Tier 2 and below, the Project Manager has the authority to add new members to the research team, and the Research Manager has the authority to assign Referees.

At Tier 3 and above, new Referees or members of the research team must be counter-approved by the Dataset Provider Representative.

### Connection

At Tier 1 and Tier 0, secure shell access to the Environment is possible without restrictions. The user should be able to set up port forwarding (redirecting a communication request from the secure Environment to the user's device) and use this to access remotely-running user interface clients from outside the Environment.

At Tier 2 and above, only remote desktop access is enabled.

We may, in future, enable secure shell access at Tier 2, but this remains a work in progress.

### Internet access

Tier 2 and above Environments have no access to the internet, other than inbound through the access connection.

Tier 0 and Tier 1 Environments have access to the open internet.

### Software ingress

For Tier 3, additional software or virtual machines arriving through the software ingress process must be reviewed and signed off by the Investigator and Referee before they can be accessed inside the Environment (with the exception of pre-approved virtual machines or package mirrors).

For Tier 0 and Tier 1, users should be able to install software directly into the Environment (in user space) from the open internet.

### Data ingress

For Tier 3 and above, the high-security data transfer process is required. Lower-security data transfer processes are allowed at Tier 2 and below.

### Copy-paste

At Tier 1 and 0 users should be permitted to copy out data when they reasonably believe their local device is secure, with the permission of the Investigator.

At Tier 2 and above, copy-paste is disabled into and out of the remote desktop. (Copy-paste within the remote desktop is possible, but the paste-buffer which stores the short-term data is remote.)

### Refereeing of classification

Independent Referee scrutiny of data classification is required when the initial classification by the Investigator and Data Provider Representative is Tier 2 or higher.
