(process_data_ingress)=

# Data ingress process

## Introduction

The Data Safe Haven has various technical controls to ensure data security.
However, the processes and contractual agreements that the **Dataset Provider** agrees to are equally important.

## Bringing data into the environment

```{attention}
Before starting any data ingress, make sure that you have gone through the {ref}`data classification process <process_data_classification>`.
```

Talk to your {ref}`role_system_manager` to discuss possible methods of bringing data into the environments.
It may be convenient to use [Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer/).
In this case you will not need log-in credentials, as your {ref}`role_system_manager` can provide a short-lived secure access token which will let you upload data.

```{tip}
You may want to keep the following considerations in mind when transferring data in order to reduce the chance of a data breach
- use of short-lived access tokens limits the time within which an attacker can operate
- letting your {ref}`role_system_manager` know a fixed IP address you will be connecting from (eg. a corporate VPN) limits the places an attacker can operate from
- communicating with your {ref}`role_system_manager` through a secure out-of-band channel (eg. encrypted email) reduces the chances that an attacker can intercept or alter your messages in transit
```
