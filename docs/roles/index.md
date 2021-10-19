# Roles
Several aspects of the Safe Haven rely on role-based access controls.
The different roles are detailed alphabetically below.

(role_data_provider_representative)=
## Dataset Provider Representative

The Dataset Provider is the organisation who provided the dataset under analysis.
The Dataset Provider should designate a single representative contact to liaise with the organisation running the Safe Haven.
This individual is the **Dataset Provider Representative**.
They are authorised to act on behalf of the Dataset Provider with respect to the dataset and must be in a position to certify that the Dataset Provider is authorised to share the dataset.

There may be additional people at the Dataset Provider who will have input in discussions around data sharing and data classification.
It is the duty of the **Dataset Provider Representative** to manage this set of stakeholders at the Dataset Provider.

- [Data ingress](data_provider_representative/data_ingress.md) -  What a **Dataset Provider Representative** needs to know about bringing data or software into the environment.
- [Data egress](data_provider_representative/data_egress.md) - What a **Dataset Provider Representative** needs to know about bringing data or software out of the environment.
- [Data classification guide](../policies/data_sensitivity_classification/classification_process.md) - Step-by-step instructions on how to classify a work package into one of our security tiers

(role_investigator)=
## Investigator

The research project lead, this individual is responsible for ensuring that project staff comply with the Environment's security policies.
A single lead **Investigator** must be responsible for a project.
Multiple collaborating institutions may have their own lead academic staff, and academic staff might delegate to a researcher the leadership as far as interaction with the SRE is concerned.
In both cases, the term **Investigator** here is independent of this - regardless of academic status or institutional collaboration, this individual accepts responsibility for the conduct of the project and its members.

- [Data classification guide](../policies/data_sensitivity_classification/classification_process.md) - Step-by-step instructions on how to classify a work package into one of our security tiers
- [Data ingress](investigator/data_ingress.md) - What an **Investigator** needs to know about bringing data or software into the environment
- [Data egress](investigator/data_egress.md) - What an **Investigator** needs to know about bringing data or software out of the environment
- [Software requests](investigator/software_package_request_form.md) - Fill out this form and send it to your {ref}`role_system_manager` to request the installation of new software in your SRE
- [Software package allowlist policy](../policies/security/software_package_approval_policy.md) - Guidance on our policy for approving software packages.

(role_programme_manager)=
## Programme Manager

A designated staff member in the research institution who is responsible for creating and monitoring projects and Environments and overseeing a portfolio of projects.
This should be a member of professional staff with oversight for data handling in one or more research domains.
The **Programme Manager** can add new users to the system and assign users to specific projects.
They assign **Project Managers** and can, if they wish, take on this role themselves.

(role_project_manager)=
## Project Manager

A staff member with responsibility for running a particular project.
This role could be filled by the **Programme Manager**, or a different nominated member of staff within the research institution.
The **Project Manager** should take charge of ensuring that all users for their project have accounts and are able to access the SRE for their project.

- [Starting a project](project_manager/project_initiation.md) - A guide for project managers who want to start new projects using a Safe Haven
- [Data ingress](project_manager/data_ingress.md) -  What a **Project Manager** needs to know about bringing data or software into the environment.

(role_referee)=
## Referee

A **Referee** volunteers to review code or derived data (data which is computed from the original dataset), providing evidence to the **Investigator** and **Dataset Provider Representative** that the researchers are complying with data handling practices.
**Referees** also play a role in classifying work packages at tier 2 or above, when they should be consulted by either the **Investigator** or the **Dataset Provider Representative** (see below).

- [Data classification guide](../policies/data_sensitivity_classification/classification_process.md) - Step-by-step instructions on how to classify a work package into one of our security tiers

(role_researcher)=
## Researcher

A project member, who analyses data to produce results. We reserve the capitalised term **Researcher** for this role in our user model.
We use the lower case term when considering the population of researchers more widely.

- [User guide](researcher/user_guide.md) - Step-by-step instructions for **Researchers** who want to start using an existing Safe Haven. (NB. the guide has been written with Turing Data Study Groups in mind).
- [Cheat sheet](researcher/user_cheat_sheet.md) - An abbreviation version of the previous guide for **Researchers**
- [Software package allowlist policy](../policies/security/software_package_approval_policy.md) - Guidance on our policy for approving software packages.

(role_system_manager)=
## System Deployer

Members of technical staff responsible for deploying the Safe Haven.
Typically these might be members of an institutional IT team or external contractors.

- [Safe Haven Management (SHM) deployment guide](system_deployer/deploy_shm.md) - Deploy a single Safe Haven Management (SHM) segment. This will deploy the user management and software package mirrors.
- [Data Science virtual machine build instructions](system_deployer/build_compute_vm_image.md) - Build and publish our "batteries included" Data Science Compute virtual machine image. Customise if necessary.
- [Secure Research Environment (SRE) deployment guide](system_deployer/deploy_sre.md) - Deploy one Secure Research Environment (SRE) for each project you want to have its own independent, isolated analysis environment.
## System Manager

Members of technical staff responsible for configuration and maintenance of the Safe Haven.
Typically these might be members of an institutional IT team.

- [Safe Haven administrator guide](system_manager/general.md) - Instructions for administrators of a Safe Haven. Includes user management and some troubleshooting steps.
- [Software package allowlist policy](../policies/security/software_package_approval_policy.md) - Guidance on our policy for approving software packages.
- [Migrating an existing SHM](system_manager/migrate_an_shm.md) - How to migrate an existing SHM
