# Data ingress process

One of the most important responsibilities of the **Project Manager** is to facilitate data transfers.
These can include code, compiled binary files or any digital document file or dataset in any machine-readable format.

## Bringing data into the environment

There are three methods of transferring data to the Data Safe Haven (in order of preference):

- Microsoft Azure Storage Explorer
- SFTP
- Physical

Ensure that the {ref}`role_data_provider_representative` and the {ref}`role_system_manager` discuss the most appropriate method to bring data into the environment.

```{danger}
Under no circumstance should sensitive data be sent via email, even if encrypted.
```

## Data ingress for a running project

If the project team need further data ingress after the project has started, ensure that you discuss this with the {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` (if applicable).
They should {ref}`reclassify <process_data_classification>` the project - if the new security tier is higher than the one in which work has already started then the data ingress **is not permitted**.

```{warning}
If ingress of new data would change the classification of a project, we suggest defining this as a new work package and deploying a new environment for it.
```

At the end of this process they should have classified the work package into one of the Data Safe Haven security tiers.
Follow the guide to [data ingress](data_ingress.md) to bring all necessary code and data into the secure research environment.
