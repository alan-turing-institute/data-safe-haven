(policy_data_classification_process)=

# Classification process

## Work Packages

Assessing the sensitivity of a dataset requires an understanding of both the base sensitivity of the information contained in the dataset and of the impact on that base sensitivity of the operations that it will undergo in the research project.
The classification exercise therefore relates to each stage of a project and not simply to the datasets as they are introduced into it.

In our model, projects are divided into **work packages**, which we use here to refer to the activities carried out within a distinct phase of work carried out as part of a project, with a specific outcome in mind.
A work package can make use of one or more datasets, and includes an idea of the analysis which the research team intends to carry out, the potential outputs they are expecting, and the tools they intend to use – all important factors affecting the data sensitivity.
Classification is carried out on work packages rather than individual datasets.

```{caution}
Classification to a tier is **not** a property of a dataset, because a dataset's sensitivity depends on the data it can be combined with, and the use to which it is put.
```

## Classification roles

In our data governance model, there are three key roles:

{ref}`role_investigator`
: The research project lead, this individual is responsible for ensuring that project staff comply with the Environment's security policies.

{ref}`role_data_provider_representative`
: A representative of the organisation who provided the dataset under analysis.
The Dataset Provider will designate a single representative contact to liaise with the {ref}`role_investigator`, authorised to certify sharing of datasets with the researchers.

{ref}`role_referee`
: A Referee volunteers to review code or derived data (data which is computed from the original dataset), providing evidence to the {ref}`role_investigator` and {ref}`role_data_provider_representative` that the researchers are complying with data handling practices.

To classify the data to be used in a project, each role representative will go through a series of questions, to help understand the legal sensitivity of the data involved, and the consequences of a data breach.

## Classification process

The {ref}`role_data_provider_representative` and {ref}`role_investigator` must agree on a classification for each work package.
If the classification is likely to be {ref}`policy_tier_2` or higher, they should also involve an independent {ref}`role_referee`.
Prior to datasets being transfered to the Data Safe Haven, it is likely that only the {ref}`role_data_provider_representative` will have access to the actual dataset(s).
The {ref}`role_investigator` (and {ref}`role_referee` if necessary) will need to make their classification judgements based on discussions with the {ref}`role_data_provider_representative`, alongside a clear description of the dataset and associated metadata such as data dictionaries.

The {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` (if applicable) should independently classify the work package using the classification flow {ref}`shown below <policy_classification_flowchart_full>`.

```{important}
For auditability, the full path of decisions made should be recorded, not just the final outcome.
```

The project should only proceed if the {ref}`role_investigator`, the {ref}`role_data_provider_representative`, and the {ref}`role_referee` (if applicable), can come to a consensus on a work package classification.
If consensus cannot be reached, the work package should be reconsidered.

```{warning}
The Data Safe Haven project does not currently {ref}`policy_tier_4` environments. If a work package is classified as {ref}`policy_tier_4` then an alternative environment will be needed.
```

If the classification is {ref}`policy_tier_3` or below, the dataset(s) should be ingressed into an environment at that Tier to which the {ref}`role_investigator` and {ref}`role_referee` (if applicable) have access, so that they can verify the classification based on complete information.
If at this point either the {ref}`role_investigator` or {ref}`role_referee` disagree with the original classification, the consensus seeking process between the Data Provider Representative, {ref}`role_investigator` and {ref}`role_referee` (if applicable) should be repeated.
If consensus cannot be achieved the dataset(s) must be deleted from the environment.

If, at any point during the project, the research team decides to analyse the data differently or for a different purpose than previously agreed, this constitutes a new work package, and should be newly classified by repeating this process.
This is also the case if the team wishes to ingress another dataset in combination, which will require {ref}`Representatives <role_data_provider_representative>` from all Dataset Providers to arrive at the same consensus as the {ref}`role_investigator` and {ref}`role_referee` (if applicable).

## Classification workflow

Flowcharts demonstrating how we classify work packages can be seen here:

(policy_classification_flowchart_full)=

```{image} full_classification_flow.png
:alt: Full data classification workflow
:align: center
```

(policy_classification_flowchart_simple)=

```{image} simple_classification_flow.png
:alt: Simplified data classification workflow
:align: center
```

## Secure data analysis

Once a work package has been classified, an appropriate SRE is instantiated depending on the tier assigned.

For the initial work package in a project, a new environment must always be deployed.
For additional work packages, the project may deploy a new environment per work package or, where appropriate, add the new work package to an existing environment deployed for the project.

When considering adding a work package to an existing environment, the **combination** of the new work package plus all existing work packages the environment has already been used for must be considered as the effective work package when making classification decisions.
The classification tier of a combination of work package(s) can never be lower than the highest classification tier of any of the individual work packages, but may be higher due to additional risks introduced by combining datasets and activities across work packages.
If the combined classification is higher than the tier associated with the existing environment, a new environment must be deployed.

```{attention}
The classification tier of an environment cannot be upgraded or downgraded "in place".
```
