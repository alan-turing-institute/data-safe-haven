(role_data_provider_representative_ingress)=

# Data ingress process

## Introduction

Your data is precious to us.
The utmost care is taken when transferring the data.
However, you will need to follow the guidance to certify we are able to ensure your security.

The Data Safe Haven has various technical controls to ensure data security.
However, the processes and contractual agreements that the **Dataset Provider** agrees to are equally important.

## Bringing data into the environment

```{attention}
Before starting any data ingress, make sure that you have gone through the {ref}`policy_data_classification_process`.
```

There are three methods of transferring data to the Data Safe Haven (in order of preference):

- {ref}`Microsoft Azure Storage Explorer <role_data_provider_representative_ingress_azure_storage_explorer>`
- {ref}`SFTP <role_data_provider_representative_ingress_sftp>`
- {ref}`Physical <role_data_provider_representative_ingress_physical>`

```{danger}
Under no circumstance should sensitive data be sent via email, even if encrypted.
```

(role_data_provider_representative_ingress_azure_storage_explorer)=

### Azure Storage Explorer

The Safe Haven is built on the Microsoft Azure platform.
The most convenient way of safely transferring data from the Dataset Provider is to use [Azure Storage Explorer](https://azure.microsoft.com/en-us/features/storage-explorer/).
You will not need log-in credentials, as your {ref}`role_system_manager` will provide a short-lived secure access token which will let you upload data.

#### Prerequisites

```{important}
- You must be able to receive a secure email.
  We recommend the [Egress secure email](https://www.egress.com/) service, which is free to setup for receiving secure emails.
- You must know the public IP address(es) that are used by the people in your organisation who will be uploading the data.
  Talk to your IT team if you're not sure what these are.
```

When your {ref}`role_system_manager` receives the IP address(es) they will send a secure email to the designated uploader.
This will contain the secure access token, which has **write**, **list** and **delete** privileges, allowing the uploader to:

- upload files
- verify that files are fully uploaded
- remove or overwrite outdated files

```{attention}
The secure access token does **not** permit files to be downloaded.
This provides additional protection in case the token is accidentally leaked.
In the event that the token is leaked, inform your {ref}`role_system_manager` who can revoke it.
```

```{danger}
Whilst the connection between your computers and our repository is one way – you can only send data, not retrieve it – if a malicious actor were to get hold of the link, they could poison your data.
```

#### Uploading your data

1. Open [Azure Storage Explorer](https://azure.microsoft.com/en-us/features/storage-explorer/)
2. Click the socket image on the left hand side

   ```{image} azure_storage_explorer_connect.png
   :alt: Azure Storage Explorer connection
   :align: center
   ```

3. On `Select Resource`, choose `Blob container`
4. On `Select Connection Method`, choose `Shared access signature URL (SAS)` and hit `Next`
5. On `Enter Connection Info`:
  - Set the `Display name` to `ingress` (or choose an appropriate name)
  - Copy the SAS URL that the administrator sent you via secure email into the `Blob container SAS URL` box and hit `Next`
6. On the `Summary` page:
  - Ensure the permissions include `Write` & `List` (if not, you will be unable to upload data and should contact the administrator who sent you the token)
  - Hit `Connect`
7. On the left hand side, the connection should show up under `Local & Attached > Storage Accounts > (Attached Containers) > Blob Containers`->`ingress (SAS)`

   ```{image} azure_storage_explorer_container.png
   :alt: Azure Storage Explorer container
   :align: center
   ```

8. You should now be able to upload data to the Safe Haven by clicking the `Upload` button, completing the ingress process

````{note}
Since you were not given read permissions, it's expected that you will receive the following warning when uploading a file. Click `Yes`.

```{image} azcopy_warning.png
:alt: Azure Storage Explorer warning
:align: center
```
````

````{error}
If you receive an error like the following

```{image} azure_storage_explorer_error.png
:alt: Azure Storage Explorer error
:align: center
```
- This means that your IP address is not one that you told the {ref}`role_system_manager` about.
- Get your IT team to check with the {ref}`role_system_manager` and change the set of IP addresses you'll be using if necessary.
````

(role_data_provider_representative_ingress_sftp)=

### SFTP

If you are unable to install Microsoft Azure Storage Explorer on your system, the next best option is to use `SFTP`.
Check that your {ref}`role_system_manager` is able to set up an SFTP server for you to access.

In order to connect:

- The {ref}`role_system_manager` should send you a secure email with the address of the SFTP server.
- They should send a separate secure email with connection details for accessing the server.
- Please **encrypt** your data before uploading it.
- Once uploaded, you should send the {ref}`role_system_manager` a secure email with the encryption key.

```{caution}
Please ensure that you use a modern encryption algorithm and a strong key to secure your data.
```

(role_data_provider_representative_ingress_physical)=

### Physically bring in a disk

Alternatively, you provide your data on a physical disk/USB stick.

- Please **encrypt** your data before putting it onto the storage device.
- Deliver/courier the device to the hosting institution.
- Send the {ref}`role_system_manager` a secure email with the encryption key.

```{caution}
Please ensure that you use a modern encryption algorithm and a strong key to secure your data.
```
