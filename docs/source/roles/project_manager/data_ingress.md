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

If the project team need further data ingress after the project has started, ensure that you discuss this with the {ref}`role_data_provider_representative`, {ref}`role_investigator` and referee (if applicable).
They should reclassify the project.
If the new security tier is higher than the one in which work has already started then the data ingress **is not permitted**.

```{warning}
If ingress of new data would change the classification of a project, we suggest determining the updated classification and deploying a new environment for it.
```

At the end of this process they should have classified the project into one of the Data Safe Haven security tiers.
