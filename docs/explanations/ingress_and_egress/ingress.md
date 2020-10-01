# Bringing data and software into the Turing Safe Haven

This document discusses bringing data or software into the environment from an external source. This process is known as ingress.

## Data ingress (data entering a secure Environment from an external source)

The policies defined here minimise the number of people who have access to restricted information before it is in the Environment.

Datasets must only be transferred from the Dataset Provider to the Turing after an initial classification has been completed and the data sharing agreement executed.

For lower tiers, where the Environment is accessible from the internet, standard secure data transfer mechanisms such as secure copy (SCP) and secure file transfer protocol (SFTP) may be used.

For higher tiers, all data transfer to the Turing should be via our secure data transfer process, which provides the Dataset Provider time-limited, write-only access to a dedicated data ingress volume from a specific location.
Prior to access to the ingress volume being provided, the Dataset Provider Representative must provide the IP address(es) from which data will be uploaded and an email address to which a secure upload token can be sent.
Once these details have been received, the Turing will open the data ingress volume for upload of data.

To minimise the risk of unauthorised access to the dataset while the ingress volume is open for uploads, the following security measures are in place:

+ Access to the ingress volume is restricted to a limited range of IP addresses associated with the Dataset Provider and the Turing.
+ The Dataset Provider receives a **write-only** upload token. This allows them to upload, verify and modify the uploaded data, but does not viewing or download of the data. This provides protection against an unauthorised party accessing the data, even they gain access to the upload token.
+ The upload token expires after a time-limited upload window.
+ The upload token is transferred to the Dataset Provider via a secure email system.

To further minimise the risk of unauthorised access to the dataset during the upload window, the Dataset Provider should take the following precautions.

+ Data should always be uploaded directly into the secure volume to avoid the risk of individuals unintentionally retaining the dataset for longer than intended.
+ After their dataset has been transferred, the Dataset Provider should immediately indicate that the transfer is complete. In doing so, they lose access to the data volume.

If consensus on data classification cannot be made from metadata, an initial conservative classification may be made to permit the data to be ingressed into a higher tier environment.
If the final classification of a work package is lower than the initial classification, the data may be egressed from this higher tier environment Environment to a new Environment matching the final classification tier.
The web management workflows should ensure that all parties have reached consensus on the classification tier at this stage before allowing analysis to begin.

## Software ingress (software entering a secure Environment from an external source)

The base data science virtual machine provided in the secure analysis Environments comes with a wide range of common data science software pre-installed.
Package mirrors also allow access to a wide range of libraries for the programming languages for which package mirrors are provided (currently Python and R).

For other languages for which no package mirror is provided, or for software which is not available from a package repository, an alternative method of software ingress must be provided.
This includes custom researcher-written code not available via the package mirrors (e.g. code available on a researcher's personal or institutional Github repositories).

For lower tier environments, the data science virtual machine has outbound access to the internet and software can be installed in the usual manner by either a normal user or an administrator as required.

For higher tier environments, the following software ingress options are available.

### Adding software to the default environment

If multiple researchers want to install the same tool, it makes sense to add it to the list of tools installed by default in the safe haven analysis environment.
Adding other software tools to the default list will go through an application process. The requester should submit a form containing the following information:

+ Software name
+ Link to installation instructions
+ Justification for requiring this tool
+ Who is going to use this tool.

This request should then be evaluated by the development team of the Turing Safe Haven. The two evaluation criteria are:

+ Has this tool been reviewed by a community of developers? Is there a process through which harmful code could have been recognised and removed?
  + Note that this does not mean a review of the code by a member of the Research Engineering team. Default tools should have a community review and development process. Bespoke code written by an individual developer is not likely to meet this criterion.
+ Will this tool be useful to additional researchers? As a rule, any default software should be used by more than 1 person.

As a general rule, code which is primarily written by researchers on any particular project should *not* be added to the default installation. Instead, such code should follow the policies for software ingress detailed below.


### Installation during virtual machine deployment

Where requirements for additional software are known in advance of the data science virtual machine being deployed to a secure analysis Environment, the additional software sucan be installed during deployment.
In this case, software installation is performed while the virtual machine is outside of the Environment with outbound internet access available, but no access to any project data.
Once the additional software has been installed, the virtual machine is ingressed to the Environment via a one-way airlock.

### Installation after virtual machine deployment

Once a virtual machine has been deployed into a secure analysis Environment, it cannot be moved outside of the Environment, as is has had access to the data in the Environment and therefore represents an unauthorised data egress risk.
As higher tier Environments do not have access to the internet, any additional software required must be brought into the Environment in order to be installed.

Software is ingressed in a similar manner as data, using a software ingress volume:

+ In **external mode** the researcher is provided temporary **write-only** access to a software ingress volume.
+ Once the Researcher transfers the software source or installation package to this volume, their access is revoked and the software is subject to a level of review appropriate to the Environment tier.
+ Once any required review has been passed, the software ingress volume is switched to **internal mode**, where it is made available to Researchers within the analysis Environment with **read-only** access.
+ For software that does not require administrative rights to install, the Researcher can then install the software or transfer the source to a version control repository within the Environment as appropriate.
+ For software that requires administrative rights to install, a System Manager must run the installation process.