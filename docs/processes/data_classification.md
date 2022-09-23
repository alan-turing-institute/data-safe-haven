(process_data_classification)=

# Classification process

Here we give an overview of the data classification process operated by the Turing, utilising our {ref}`sensitivity tiers <policy_classification_sensitivity_tiers>`.

```{caution}
While organisations deploying their own Data Safe Haven instance are free to take inspiration from the Turing's information governance processes, each organisation is responsible for instituting their own information governance processes appropriate to their own contexts.
```

Projects are divided into {ref}`work packages <classification_work_packages>`.
Each project may have one or more {ref}`work packages <classification_work_packages>`, each of which will have an associated {ref}`sensitivity tier <policy_classification_sensitivity_tiers>`.
The sensitivity of any {ref}`work package <classification_work_packages>` depends on both the {ref}`sensitivity tier <policy_classification_sensitivity_tiers>` of the underlying data and the work that will be carried out on that data.
Research for a given {ref}`work package <classification_work_packages>` must only be undertaken in an environment suitable to the {ref}`sensitivity tier <policy_classification_sensitivity_tiers>` of the {ref}`work package <classification_work_packages>` and with the associated non-technical information governance controls in place.

(classification_work_packages)=

## Work Packages

A work package is a distinct piece of work carried out as part of a project, with a specific outcome in mind.
It can make use of one or more datasets.
A work package should encompass: the analysis that the research team intend to carry out, the expected outputs and the tools they plan to use.
We assume that classification will be carried out on work packages rather than individual datasets.

```{caution}
Classification to a tier is **not** a property of a dataset, because a dataset's sensitivity depends on the data it can be combined with, and the use to which it is put.
```

## Classification roles

There are three key roles:

{ref}`role_investigator`
: The research project lead, this individual is responsible for ensuring that project staff comply with the Environment's security policies.

{ref}`role_data_provider_representative`
: A representative of the organisation who provided the dataset under analysis.
The Dataset Provider will designate a single representative contact to liaise with the {ref}`role_investigator`, authorised to certify sharing of datasets with the researchers.

{ref}`role_referee`
: A Referee volunteers to review code or derived data (data which is computed from the original dataset), providing evidence to the {ref}`role_investigator` and {ref}`role_data_provider_representative` that the researchers are complying with data handling practices.

To classify the data to be used in a project, each role representative will go through a series of questions to help understand the legal sensitivity of the data involved and the consequences of a data breach.

## Initial classification process

The {ref}`role_data_provider_representative` and {ref}`role_investigator` should classify each work package, based on a clear understanding of what the work involves.
These two people should agree on a classification before the work can proceed.
For {ref}`policy_tier_2` and {ref}`policy_tier_3` {ref}`work packages <classification_work_packages>` the {ref}`role_referee` must also agree on the classification.
This classification will indicate which security controls should be applied when initialising the {ref}`Secure Research Environment <design_sre>` for the project.

In this documentation we will assume that the outcome of the classification is one of our {ref}`sensitivity tiers <policy_classification_sensitivity_tiers>`, but your organisation may classify projects differently and require different technical and non-technical controls.
