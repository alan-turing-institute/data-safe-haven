# Data egress process

Data Safe Havens are used for doing secure data research.
Once the project is finished, it is important to extract all outputs from the environment before shutting it down.
Each time you egress data from the environment, it must be checked to ensure that it is safe and appropriate to release.

```{note}
You might want to define multiple data collections for egress, which would each have their own sensitivity.
For example, you might separate a low-sensitivity written report from a high-sensitivity derived dataset.
The egress process can then be adjusted based on the sensitivity of each dataset.
For example, the low-sensitivity report can be publically released whereas the high-sensitivity derived dataset may go back to the data provider only.
```

## Bringing data out of the environment

As for [data ingress](data_ingress.md), there are three methods of transferring data out of the Data Safe Haven (in order of preference):

- Microsoft Azure Storage Explorer
- SFTP
- Physical

Ensure that the {ref}`role_data_provider_representative` and the {ref}`role_system_manager` discuss the most appropriate method to bring data out of the environment.

```{danger}
Under no circumstance should sensitive data be sent via email, even if encrypted.
```
