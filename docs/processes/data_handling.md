(process_data_handling)=

# Data Handling

## Data classification

Before any project starts, it should go through an assessment process to classify it into a {ref}`sensitivity tier <policy_classification_sensitivity_tiers>`.
A full overview of the classification process can be found {ref}`here <process_data_classification>`.

## Data sharing agreement

A formal data sharing agreement should be drawn up between the {ref}`role_organisation_data_provider` and the {ref}`role_organisation_dsh_host`.
This should be drafted with the benefit of legal advice and signed before any dataset is transferred.

```{hint}
Your organisation might have a template agreement that can be used to minimise the turnaround time and legal effort required.
```

## User lifecycle

Projects should be recorded in a centralised system.
Once a user's involvement with a project or work package ends their access should be revoked promptly.

(process_data_security_training)=

## Data security training requirements

We recommend requiring data security awareness training for the following categories of person:

- Anyone with administrator access to the `Data Safe Haven` codebase. This is to ensure integrity of the code supply chain.
- Anyone responsible for deploying a Data Safe Haven.
- {ref}`System Managers <role_system_manager>` administering a deployed Data Safe Haven.
- Anyone who has administrator access to the Azure subscriptions hosting any deployed Data Safe Haven.
- {ref}`Programme <role_programme_manager>` and {ref}`project managers <role_project_manager>`.
- All {ref}`Researchers <role_researcher>` with access to any data in scope of the NHS Data Security and Protection Toolkit (DSPT) held in a Data Safe Haven.
- {ref}`Data Provider Representatives <role_data_provider_representative>`, {ref}`Investigators <role_investigator>` and {ref}`Referees <role_referee>` for any project containing data in scope of DSPT.

```{hint}
The exact training requirements for each organisation will depend on their own information governance processes.
```

## Data security incident process

We recommend that {ref}`System Managers <role_system_manager>` follow the data security incident process of the {ref}`role_organisation_dsh_host`.
You may additionally want to consider developing an additional data security policy specific to your own Data Safe Haven instance on top of this.
