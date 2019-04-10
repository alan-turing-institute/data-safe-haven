Sensitive Data Handling at the Turing - Overview for Data Providers
===================================================================

Introduction
------------

Secure environments for analysis of sensitive datasets are essential for research.

Such "data safe havens" are a vital part of the research infrastructure.

It is essential that sensitive or confidential datasets are kept secure, both to enable for analysis of 
personal data in a manner that is capable of being compliant with data protection law, 
but to preserve the social license to carry out research activities.

To create and operate these safely, efficiently, and usably, requires, as with many sociotechnical systems, a complex stack of interacting 
business process and design choices. This document describes the approaches taken by the Alan Turing Institute when building and managing environments for productive, secure, collaborative research projects.

We propose choices for the security controls that should be applied in the areas of:

* data classification
* data reclassification 
* data ingress
* data egress
* software ingress
* user access
* user device management
*  analysis environments

We do this for each of a small set of security "Tiers" - noting that the choice of security controls depends on the sensitivity of the data.

This document describes our approach to handling research data. It does not cover the institute's core enterprise information security practices, which are described elsewhere. Nor do we cover the data-centre level or organisational management security practices which are fundamental to any secure computing facility - we do not operate our own data centres, but rely on upstream ISO 270001 compliant data centre provision in Microsoft Azure and the Edinburgh Parallel Computing Centre.

We have also omitted some details about the processes by which sensitive data is transferred to and from the internet, the lifecycle for vetting, creation and deletion of research users

Software-defined Infrastructure
-------------------------------

Our approach - separately instantiating an isolated environment for each project - is only possible without a hugely
inefficient duplication of effort because of the advent of "software defined infrastructure".

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

A software defined infrastructure platform, on which to build,
is a requirement for a well-defined secure research environment. It allows for separation of concerns between
core IT services and the research e-Infrastructure community.

It also means that the definition of the research environment can be meaningfully audited - 
as no aspect of it is not described formally in code, it can be fully scrutinised.

In this document, we do so at a high level, describing in general terms what should be built,
and in particular, what restrictions should be applied at which tiers.

A model for secure data research projects
-----------------------------------------

![The Turing model for secure data research]()

### Environments and Projects 

Assessing the sensitivity of a dataset requires an understanding of the base sensitivity of the information contained in the dataset and of the impact on that base sensitivity of the operations that it will undergo in the research project. 
The classification exercise therefore relates to each stage of a project and not simply to the datasets as they are introduced into it.

Classification to a tier is therefore a property of an Environment: the project, a subset of its tasks, and a collection of datasets. It is not a property of a dataset, because a particular dataset's sensitivity depends on the data it can be combined with, and the use to which it is put.
A project will create one or more secure research environments corresponding to the stages of the project, and the current tasks in operation.

### Researcher

A project member, who analyses data to produce results. We reserve the capitalised term ``Researcher'' for this role
in our user model. We use the lower case term when considering the population of researchers more widely.

### Investigator

The research project lead, this individual is responsible for ensuring that the project staff comply with
the haven's security policies. A single lead investigator must be responsible for a project. Multiple collaborating institutions may have
their own lead academic staff, and academic staff might delegate to a researcher the leadership as far as interaction with the secure environment is concerned.
In both cases, the term Investigator here is independent of this - regardless of academic status or institutional collaboration, this individual accepts responsibility for the conduct of the project and its members.

### Referee

A Referee volunteers to review code or derived data, providing evidence to the investigator and Dataset Provider Representative that the researchers are complying with data handling practices. The importance of an independent Referee for sensitive data handling is discussed futher in section~\ref{sec:review}.

### Dataset Provider and Representative

The representative contact to the research institution of the organisation who provided the dataset under analysis.

The Dataset Provider will designate an individual representative to liaise with the research institution.
That individual will certify that the Dataset Provider is authorised  to share the dataset with the research institute.

The web management interface will be used to manage any transitions of this responsibility between personnel at the Dataset Provider.

Dataset Provider Representatives must be given accounts within the research institute's system to monitor the use to which their datasets
are put and the process of data classification, ingress, reclassification and egress.

There may be additional people at the Data Provider who will have input in discussions around data sharing and data classification.
It is the duty of the Dataset Provider Representative to manage this set of stakeholders at the Dataset Provider.

### Research Manager

A designated staff member in the research institution who is responsible for creation and monitoring of projects and environments.
This should be a member of professional staff with oversight for data handling in one or more research domains.

### System Manager 

Members of staff responsible for configuration and maintenance of the secure research environment.

Environment Tiers
-----------------

Our recommendation for secure information processing tiers is not new: they correspond to UK government classifications\cite{classifications}, and reconcile these to the definitions of personal data, whether or not 'special category', under the GDPR, and relate these to common activities in the research community. 
In this paper, by `sensitive datasets' we mean datasets with confidentiality restrictions and/or which are subject to data protection law (DPL).

We emphasise that these are based on considering the sensitivity of all information handled in the project, including information generated by
combining or processing input datasets. In every case, the categorisation does not depend only on the input datasets, but on combining information
with other information or generated results.

Derived information may be of higher security tier than the information in the input datasets.
(For example, information on the identities of those who are suspected to possess an undiagnosed neurological condition on the basis of analysis of public social media data.) Where a project team believes this will be the case, the datasets should be transferred to the higher tier of secure environment \emph{before} the project commences.

If it becomes apparent during the project that intended analysis will produce this effect then the datasets should be transferred to the relevant higher security tier environment before that analysis is carried out.

In the below, ``personal data'' follows the GDPR definition: information linked to living individuals. It excludes information about individuals who
are dead.

### Tier 0

Tier zero environments are used to handle publicly available, open information, where all generated and combined
information is also suitable for open handling. [Flowchart spuriously has 'for use in research']

Tier 0 applies where information
processed, combined or generated does not include personal data.

Although this data is open, there are still advantages to handling it through a managed data analysis infrastructure. 

Management of Tier 0 data in a visible, well ordered infrastructure provides confidence to stakeholders as to the handling of more sensitive datasets. 

Although analysis may take place on personal devices, the data should still therefore be listed through the inventory and curatorial systems of a managed research data environment.

Finally, audit trails as to the handling of Tier 0 information mitigate the risk attendant on misclassification.

### Tier 1

Tier one environments are used to handle, process and generate
data that is intended for eventual publication or could be published without reputational damage. 

Information that is kept private to give the research team a competitive advantage, not as a protection for the information.

Both the information and the proposed processing must otherwise meet the criteria for Tier 0.

It may be used for pseudonymised or synthetic information generated from personal data, where one has absolute 
confidence in the quality of pseudonymisation. This makes the information no longer personal data. 
The risk of processing it so that individuals are capable of being re-identified must be considered as part of the classification process.

### Tier 2

Tier 2 environments are used to handle, combine or generate information which is not linked to living individuals.

It may be used for pseudonymised or synthetic information generated from personal data, where we have strong, but not absolute,
confidence in the quality of pseudonymisation. This makes the information no longer personal data, but the risk of processing it so that individuals are capable of being re-identified must be considered as part of the classification process.


The pseudonymisation process itself, if carried out in the research organisation, should take place in a Tier-3 environment.
See section \ref{sec:egress} for a full discussion of audit of pseudonymisation code.


A typical model for a project will be to instantiate both tier 2 and tier 3 environments, with pseudonymised or synthetic data generated in 
the tier 3 environment and then transferred to the tier 2 environment.


Tier 2 environments are also used to handle, combine or generate information which is confidential, but not, in commercial or national security terms, sensitive.
Tier 2 corresponds to the government OFFICIAL classification.
They includes commercial-in-confidence datasets or intellectual property where the consequences of legal or financial consequences from disclosure are low.

At Tier 2 and above, reclassification of the results of the project for publication must be run following a careful process, described in section~\ref{sec:reclassification}. Derived information must otherwise be maintained as confidential.

At Tier 2, the most significant risks are `workaround breach` and the risk of  mistakenly believing data is robustly
pseudonymised, when in fact re-identification might be possible.

### Tier 3

Tier 3 environments are used to handle, combine or generate personal data, excluding personal data where there is a risk that disclosure might pose a substantial threat to the personal safety, health or security of the data subjects.

It also includes pseudonymised or synthetic information generated from personal data, where we have only weak
confidence in the quality of pseudonymisation.

Tier 3 environments are also used to handle, combine or generate information, including intellectual property, which is sensitive in commercial or national 
security terms. 
This tier anticipates the need to defend against compromise by attackers with bounded capabilities and resources.
This may include hacktivists, single-issue pressure groups, investigative journalists, competent individual hackers and the majority of criminal individuals and groups.
The threat profile excludes sophisticated, well resourced and determined threat actors, such as highly capable serious organised crime groups and state actors.
This corresponds to the governmental ‘OFFICIAL–SENSITIVE’ categorisation. \cite{classifications}

The difference between Tier 2 and Tier 3 environments is the most significant in this model, as it carries the highest consequences, both for researcher productivity and organisational risk. 

At Tier 3, the risk of hostile actors attempting to break into the secure environment becomes significant.

### Tier 4

Tier 3 environments are used to handle, combine or generate personal data 
where disclosure poses a substantial threat to the personal safety, health or security of the data subjects.

It also includes handling, combining or generating datasets which are sensitive in commercial or national 
security terms, and are likely to be subject to attack by sophisticated, 
well resourced and determined actors, such as serious organised crime groups and state actors. This
corresponds to the UK governmental `SECRET' categorisation~\cite{classifications}.

It is at Tier 4, that the risk of hostile actors penetrating the project team becomes significant.

Software library distributions
------------------------------

Maintainers of shared research computing environments face a difficult challenge in keeping research algorithm libraries and platforms
up to date - and in many cases these conflict. The use of single-project virtual environments opens another possibility: downloading the software as neeeded for the project
from package managers such as the Python package index. To achieve this in a secure environment, without access to the
external internet, requires maintainance of mirrors of package repositories inside the environment. 

Use of package mirrors inside the environment means that the set of default installed packages can be kept
to a minimum, reducing the likelihood of encountering package-conflict problems and saving on
System Manager time.

At some tiers, however, not all software in the public repositories should be immediately mirrored.
Malicious software has occasionally been able to become an official download on official package mirrors. 
This is a low risk, since the environment will not have access to the internet, but must still be guarded against at the higher tiers.

Implemeters should therefore choose at some tiers to mirror only whitelisted packages, or to mirror the full package list but with a delay
(during which the community will catch most malicious code on package mirrors.)

Storage
-------

What storage volumes should exist in the analysis environment?

A Secure data volume is a read-only volume that contains the secure data for use in analyses. It is mounted read-only
in the analysis environments that must access it. One or more such volumes will be mounted depending on how many managed secure datasets the environment has access to.

A Secure document volume contains electronically signed copies of agreements between the Data Provider and the
research institution.

A Secure scratch area is a read-write volume used for data analysis. Its contents must be automatically and regularly deleted.

An Output volume is a read-write area intended for the extraction of results, such as figures for publication. See~\ref{sec:egress} below.

The Software volume is a read-only area which contains software used for analysis. 

A Home area is a smaller read-write volume used for local programming and configuration files. It should not be used for data analysis outputs, though this is enforced only in policy, not technically. Configuration files for software in the software volume should point to the Home Area.

User Devices
------------

What devices should researchers use to connect to the secure research environment?

We define two types of devices: 

\begin{itemize}
    \item Open devices
    \item Managed devices
\end{itemize} 

### Managed devices

Managed devices do not have administrator/root access.

They have an extensive suite of research software installed.

This include the ability to install packages for standard programming environments without use of root (e.g. \verb|pip install, brew install.)|

Researchers can compile and run executables they code in User Space.

### Open Devices

Staff researchers and students should be able to choose that an employer-supplied device should instead have an administrator/root account to which they do have access.
These devices are needed by researchers who work on a variety of bare-metal programming tasks.

However, such devices must not be able to access higher tier secure environments

\subsection{User device networks}

Our recommended network security model requires research organisations to create two dedicated research networks for
user devices.

\begin{itemize}
    \item An Open network
    \item A Restricted network
\end{itemize}

The open research network corresponds to Eduroam access - it is assumed the whole research community can access this network, and restriction
by IP address to data environments is not possible on the open network.

Restricted networks may be linked between multiple institutions (such as partner research institutions), so that researchers travelling to collaborators' sites will be able to connect to restricted networks, and thus to secure environments, while away from their home institution.

Access to the restricted network via VPN should not be possible.

Firewall rules for the environments must enforce restricted network IP ranges corresponding to these networks.

Of course, secure environments themselves should, at some tiers, be restricted from accessing anything outside an isolated network for that secure research environment.

Physical security
-----------------

Some data requires a physical security layer around not just the data centre,
but the place users use to connect to it.

We distinguish three levels of physical security for research spaces:

* Open research spaces
* Medium security research spaces
* High security research spaces

Open research spaces include university libraries, cafes and common rooms.

Medium security research spaces control the possibility of unauthorised viewing.
Card access restricting entry to employees is required.

Private offices, or small group offices with partitions or screen modifications
to prevent ``visual evesdropping'' are the norm.
In large open plan offices, additional partitions may be suitable.

Secure research spaces control the possibility of the researcher deliberately
removing data. Devices will be locked to appropriate desks, and neither enter nor leave 
the space. Mobile devices should be removed before entering, to block the 'photographic hole',
where mobile phones are used to capture secure data from a screen.

Firewall rules for the environments must enforce restricted network IP ranges corresponding to these 
research spaces.

Data reclassification
---------------------

From a  project, datasets can often be created which merit use in an environment with a lower classification.

For example, data may be pseudonymised, bringing it from Tier 3 to Tier 2, or used to build into a trained model, which might become Tier 1, or aggregated into a summary statistic, and published as Tier 0.

However, the assertion that a derived data artefact indeed merits a lower tier cannot be made without challenge:
understanding the possibility of personal data leaking through generated pseudonymised, synthetic or other derived datasets 
is a delicate endeavour.

Pseudonyimised datasets can, on linking to another published dataset, become identifiable.

We therefore require the reclassification process to certify an authors' claims about the script which was used to produce the derived data artefact,
and that identifiable data is not released.

No reclassification should be permitted without a script describing, in code, the process used to create the derived dataset. 
(The authors do not believe that a spreadsheet can be properly so audited.)

A reclassification script should be written by a project member. This is placed on the software volume or home volume, and run so that the derived
dataset is placed on the Output Volume.

Following appropriate review of the reclassification script and generated derived dataset (see~\ref{sec:review}), a new environment can be created with the former egress volume now mounted as a new secure data volume within a new environment, at a different tier. The existence of this environment as a ``derived environment'' should be noted, with the originating other environment's ID and the reclassification script preserved.

Software Ingress
----------------

As discussed above, package mirrors allow ingress of standard software.

But since we forbid copy-paste, how should researcher-written software, written outside the secure
environment, arrive inside?

If we allow access to the internet to `git clone` such software, this might allow for data to leave the environment, and at higher tiers, there is no access to the open internet. 

Instead, for researcher-written code developed elsewhere, other software, implementers should use an \textbf{airlock policy}: installation should be performed in an isolated environment without access to the data. After the installations are completed, internet access must then be disabled and data access enabled. 

For software that does not require admin rights to install:

In **install mode**, internet access is opened and data and scratch volumes are not accessible. Software can be downloaded and installed. 

In **analysis mode**, internet access is disabled and data and scratch volumes are accessible.

For software that requires admin rights to install:

In **install mode** A virtual machine is created outside of the secure environment. The user has administrator privileges on the machine and can install any software necessary from the open internet. There is no access to the secure data during this process.

In **analysis mode**, the VM image is moved into the secure environment where internet access is disabled. 

The process to switch volumes between these modes should be managed through a process in the web-based management software.

The choices
------------

Having described the full model, processes, and lifecycles, we can now enumerate the list of choices that
can be made for each Environment. These should all be separately configurable on an environment-by-
environment bassis. However, we make recommendations for these choices at each tier.

### Package mirrors

At tier 3 and higher, package mirrors should include only white-listed software.

At tier 2, package mirrors should include all software, one month behind the reference package server.
Critical security updates should be fast-tracked.

At tier 1 and 0, installation should be from the reference package server on the external internet.

### Inbound network

Only the Restricted network will be able to access Tier 3 and above, and only via the access node.

Open network should be able to access only Tier 2 and below.

### Outbound network

At Tier 1 and 0 the internet is accessible from inside the research environment,
at all other tiers the virtual network inside the environment is completely isolated.

### User devices

Open devices should not be able to access the Restricted network.

Managed laptop devices should be able to leave the physical office where the Restricted network exists, but should have no access to Tier 3 or above environments while 'roaming'.

### Physical security

Tier 2 and below environments should not be subject to physical security.

Tier 3 environments should require the limited access space.

Tier 4 access must be from the high security space.

### User management

At Tier 2 and below, the Investigator has the authority to add new members to the research team, and the research manager has the authority to assign Referees.

At Tier 3 and above, new members of the research team or Referees must be counter-approved by the Dataset Provider Representative.

### Connection

At Tier 1 and Tier 0, ssh access to the enviroment is possible without restrictions. The user should be able to set-up port forwarding (ssh tunnel) and use this to access remotely-running UI clients via a native client browser.

At Tier 3, only remote desktop access is enabled.

At Tier 2, we are unsure at this stage if our objective to enable restricted SSH access to this
tier is possible. In the interim, only remote desktop access is enabled.

### Internet access

Tier 2 and above environments have no access to the internet, other than inbound through the 
access connection

Tier 0 and Tier 1 environments have access to the internet.

### Software ingress

For Tier 3,
the Investigator and Referee must review and sign off on software or virtual machines arriving through the software
ingress process (excluding package mirrors) before it can be accessed inside the environment.

For Tier-0 and Tier-1, users should be able to install software directly into the environment (in user space) from the open internet.

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
