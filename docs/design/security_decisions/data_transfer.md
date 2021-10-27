# Data transfer

The Data Safe Haven aims to implement a high security transfer protocol.
This protocol limits the following aspects of the transfer to provide the minimum necessary exposure:
+ The time window during which dataset can be transferred
+ The networks from which it can be transferred
+ The people and devices who are able to initiate data transfer


```{tip}
If possible, a time limited or one-time access token, providing write-only access to the secure volume, should be used for all data transfers.
```

## Preferred data transfer process

The above protocol is implemented using in Azure as follows:

+ A separate Azure storage account is created for each project which is only accessible by {ref}`System Managers <role_system_manager>`.
+ Each Data Provider has an independent storage container within this account
+ A set of IP addresses is communicated to the {ref}`role_system_manager` by the {ref}`role_data_provider_representative`.
+ The {ref}`role_system_manager` grants access permission to this IP address range while excluding other connections.
+ The {ref}`role_system_manager` generates a time-limited Shared Access Signature (SAS) token with write, list and append permissions for the relevant storage container.
+ The {ref}`role_system_manager` sends the SAS token to the {ref}`role_data_provider_representative` over a secure channel.
+ The {ref}`role_data_provider_representative` uses the SAS token to upload their data.

```{important}
Excluding **read** and **download** permissions from the SAS token provides an added layer of protection against loss or interception of the token.
```

```{important}
Limiting the validity of the SAS token minimises the chance of malicious actors at the Data Provider poisoning the data upload.
```

We strongly recommend that the above process is used to securely transfer data to the Data Safe Haven.
