# Recommended security policies

## Data classification

Before data is imported into a Safe Haven it must go through an assessment process to classify it into one of 5 sensitivity tiers (from least sensitive at Tier 0, to most sensitive at Tier 4).
This classification is conducted by the dataset provider's representative, the research project lead (Investigator) and an independent adviser (Referee). Currently, the data safe haven only covers data categorised as tier 2 or 3. A full overview of the classification process can be found [here](https://github.com/alan-turing-institute/data-safe-haven/blob/master/docs/explanations/classification/classification-overview.md).

## Data sharing agreement

This should be a formal data sharing agreement as required under data protection law, drafted with the benefit of legal advice.
It should be signed after the initial classification of a work package but before any dataset is received.
Where the Dataset Provider is not the owner of all the dataset(s) covered by the data sharing agreement, the agreement must specify the legal basis under which the Dataset Provider is permitted to share this data.
This agreement should include any specific commitments required from Researchers working with the dataset.
The Alan Turing Institute has a template agreement that can be used to minimise the turnaround time and legal effort required.

The classification tier may potentially be raised from that agreed prior to data ingress, once the Investigator and Referee have had a chance to view the actual data.
The classification tier for later work packages in a project may also be higher than that for the original work package, depending on the planned analysis and any additional data required.
We therefore recommend that the data sharing agreement is worded to permit this.

## User lifecycle

Projects should be recorded in a centralised system.
They should be created by a {ref}`role_programme_manager` who then assigns a {ref}`role_project_manager` to them.
The {ref}`role_project_manager` should record the {ref}`role_investigator` and {ref}`role_data_provider_representative` as well as the {ref}`role_referee` (if applicable).
{ref}`Project Managers <role_project_manager>` also determine which {ref}`Researchers <role_researcher>` belong to each specific projects or work package.

{ref}`Researchers <role_researcher>` who wish to have access to the SRE first complete a form certifying they understand the confidentiality requirements.
If a project or work package requires any specific additional commitments then all {ref}`Researchers <role_researcher>`, {ref}`Investigators <role_investigator>` and {ref}`Referees <role_referee>` must agree to these before being granted access.0

A {ref}`role_system_manager` creates an account for them within the SHM and adds them to the appropriate group(s).
The {ref}`role_researcher` activates their account, setting their own password and multi-factor authentication.

A {ref}`role_system_manager` should remove all users from a project or work package promptly once their involvement with it ends.

## Data security incident process

The Safe Haven follows the Alan Turing Institute's data security incident process which can be found [here](https://turingcomplete.topdesk.net/tas/public/ssp/content/detail/knowledgeitem?origin=sspTile&unid=6c4590be2c74466497f5239915717621&from=7c877b26-e14b-400c-9097-ae99267258fe).
As an additional measure, as soon as a potential data security incident were to be identified, the affected SRE would be shut down to ensure the integrity of the data.
An investigation would be conducted with the Data Security Team to identify any other potentially breached SREs and also shut these down.

## Data back-up policy

As the Safe Haven is not the canonical source of data we choose not back-up the data stored in any SRE.
Since storing backups increases the risk of data breach while the cost of reimporting the data is minimal this is an acceptable risk.
