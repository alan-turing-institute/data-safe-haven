# Recommended security policies

## Data classification

Before data is imported into a Safe Haven it must go through an assessment process to classify it into one of five {ref}`sensitivity tiers <policy_classification_sensitivity_tiers>`.
This classification is conducted by the {ref}`role_data_provider_representative`, the research project lead ({ref}`role_investigator`) and an independent adviser ({ref}`role_referee`).
The least sensitive category is Tier 0, and most sensitive is Tier 4 - currently, we recommend the use of the Data Safe Haven for projects in tiers 2 or 3.
A full overview of the classification process can be found `here <policy_data_classification_process>`.

## Data sharing agreement

This should be a formal data sharing agreement as required under data protection law, drafted with the benefit of legal advice.
It should be signed after the initial classification of a work package but before any dataset is received.
Where the Dataset Provider is not the owner of all the dataset(s) covered by the data sharing agreement, the agreement must specify the legal basis under which the Dataset Provider is permitted to share this data.
This agreement should include any specific commitments required from Researchers working with the dataset.

```{hint}
Your organisation might have a template agreement that can be used to minimise the turnaround time and legal effort required.
```

The classification tier may potentially be raised from that agreed prior to data ingress, once the {ref}`role_investigator` and {ref}`role_referee` have had a chance to view the actual data.
The classification tier for later work packages in a project may also be higher than that for the original work package, depending on the planned analysis and any additional data required.
We therefore recommend that the data sharing agreement is worded to permit this.

## User lifecycle

Projects should be recorded in a centralised system.
They should be created by a {ref}`role_programme_manager` who then assigns a {ref}`role_project_manager` to them.
The {ref}`role_project_manager` should record the {ref}`role_investigator` and {ref}`role_data_provider_representative` as well as the {ref}`role_referee` (if applicable).
{ref}`Project Managers <role_project_manager>` also determine which {ref}`Researchers <role_researcher>` belong to each specific projects or work package.

{ref}`Researchers <role_researcher>` who wish to have access to the SRE first complete a form certifying they understand the confidentiality requirements.
If a project or work package requires any specific additional commitments then all {ref}`Researchers <role_researcher>`, {ref}`Investigators <role_investigator>` and {ref}`Referees <role_referee>` must agree to these before being granted access.

- A {ref}`role_system_manager` creates an account for them within the SHM and adds them to the appropriate group(s).
- The {ref}`role_researcher` activates their account, setting their own password and multi-factor authentication.

```{important}
A {ref}`role_system_manager` should remove all users from a project or work package promptly once their involvement with it ends.
```

(policy_data_security_training)=

## Data security training requirements

We recommend requiring data security awareness training for the following categories of person:

- Anyone with administrator access to the Data Safe Haven GitHub (including organisational admins). This is to ensure integrity of the code supply chain.
- {ref}`System Managers <role_system_manager>` for any deployed Data Safe Haven
- Anyone who has administrator access to the Azure subscriptions hosting any deployed Data Safe Haven.
- {ref}`Programme <role_programme_manager>` and {ref}`project managers <role_project_manager>`.
- All {ref}`Researchers <role_researcher>` with access to any data in scope of DSPT held in a Data Safe Haven.
- {ref}`Data Provider Representatives <role_data_provider_representative>`, {ref}`Investigators <role_investigator>` and {ref}`Referees <role_referee>` for any project containing data in scope of DSPT.

The requirement is documented proof of (within 1 year):

- Organisational Data Protection training
- Organisational Information Security training
- [NHS Data Security Awareness training](https://www.e-lfh.org.uk/programmes/data-security-awareness)

or equivalent qualifications from another organisation.

## Data security incident process

We recommend that {ref}`System Managers <role_system_manager>` follow the data security incident process of the wider organisation.
As an additional measure, as soon as a potential data security incident is identified, the affected SRE should be shut down to ensure the integrity of the data.
An investigation should be conducted in conjunction with your organisation's data security team to identify any other potentially breached SREs and also shut these down.

## Data back-up policy

As the Safe Haven is not the canonical source of data we choose not back-up the data stored in any SRE.
Since storing backups increases the risk of data breach while the cost of reimporting the data is minimal this is an acceptable risk.
