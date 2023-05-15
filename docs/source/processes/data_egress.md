(process_data_egress)=

# Data egress process

The outputs of the work being done in a Data Safe Haven are also stored in the SRE.
There are technical and policy controls that must be satisfied before any data can be brought out of the Data Safe Haven.

## Classification

The first stage of egressing outputs is to classify them.
This follows the {ref}`same workflow <process_data_classification>` as for {ref}`data ingress <process_data_ingress>`.

```{hint}
Get the same people who ran the ingress classification process to do this - {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` (optional).
```

```{note}
Each time you want to bring code or data out of the environment, you'll have to classify this data as a new work package.
```

Once the outputs are classified, the classification team should let the {ref}`role_system_manager` know who will be performing the egress and how they want this to be done.

## Bringing data out of the environment

Talk to your {ref}`role_system_manager` to discuss possible methods of bringing data out of the environments.
It may be convenient to use [Azure Storage Explorer](https://azure.microsoft.com/en-us/products/storage/storage-explorer/).
In this case you will not need log-in credentials, as your {ref}`role_system_manager` can provide a short-lived secure access token which will let you upload data.

```{tip}
You may want to keep the following considerations in mind when transferring data in order to reduce the chance of a data breach
- use of short-lived access tokens limits the time within which an attacker can operate
- letting your {ref}`role_system_manager` know a fixed IP address you will be connecting from (eg. a corporate VPN) limits the places an attacker can operate from
- communicating with your {ref}`role_system_manager` through a secure out-of-band channel (eg. encrypted email) reduces the chances that an attacker can intercept or alter your messages in transit
```
