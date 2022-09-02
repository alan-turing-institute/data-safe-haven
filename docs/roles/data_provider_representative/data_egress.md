(role_data_provider_representative_egress)=

# Data egress process

The outputs of the work being done in a Data Safe Haven are also stored in the SRE.
There are technical and policy controls that must be satisfied before any data can be brought out of the Data Safe Haven.

## Classification

The first stage of egressing outputs is to classify them.
This follows the {ref}`same workflow <process_data_classification>` as for {ref}`data ingress <role_data_provider_representative_ingress>`.

```{hint}
Get the same people who ran the ingress classification process to do this - data provider representive, investigator and referee (optional).
```

```{note}
Each time you want to bring code or data out of the environment, you'll have to classify this data as a new work package.
```

Once the outputs are classified, the classification team should let the {ref}`role_system_manager` know who will be performing the egress and how they want this to be done.

## Downloading data from the environment

As for ingress, there are three methods for transferring data out of the Data Safe Haven (in order of preference):

- {ref}`Microsoft Azure Storage Explorer <role_data_provider_representative_egress_azure_storage_explorer>`
- {ref}`SFTP <role_data_provider_representative_egress_sftp>`
- {ref}`Physical <role_data_provider_representative_egress_physical>`

```{danger}
Under no circumstance should sensitive data be sent via email, even if encrypted.
```

(role_data_provider_representative_egress_azure_storage_explorer)=

### Azure Storage Explorer

Similarly to the {ref}`equivalent data ingress process <role_data_provider_representative_egress_azure_storage_explorer>`

```{important}
- You must be able to receive a secure email.
- You must know the public IP address(es) that are used by the people in your organisation who will be downloading the data.
```

When your {ref}`role_system_manager` receives the IP address(es) they will send a secure email to the designated uploader.
This will contain the secure access token, which has **read** and **list** privileges, allowing the downloader to:

- download files
- view all files available for download

```{attention}
The secure access token does **not** permit files to be uploaded or deleted.
This provides additional protection in case the token is accidentally leaked.
In the event that the token is leaked, inform your {ref}`role_system_manager` who can revoke it.
```

```{danger}
Note that a malicious actor in your permitted IP address range (for example at your organisation) who gets hold of the token **will** be able to download these outputs.
```

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

8. You should now be able to download data to the Safe Haven by clicking the `Download` button, completing the egress process

````{error}
If you receive an error like the following

```{image} azure_storage_explorer_error.png
:alt: Azure Storage Explorer error
:align: center
```
- This means that your IP address is not one that you told the {ref}`role_system_manager` about.
- Get your IT team to check with the {ref}`role_system_manager` and change the set of IP addresses you'll be using if necessary.
````

(role_data_provider_representative_egress_sftp)=

### SFTP

If you are unable to install Microsoft Azure Storage Explorer on your system, the next best option is to use `SFTP`.
Check that your {ref}`role_system_manager` is able to set up an SFTP server for you to access.

In order to connect:

- The {ref}`role_system_manager` should send you a secure email with the address of the SFTP server.
- They should send a separate secure email with connection details for accessing the server.
- You should be able to use these details to download the **encrypted** outputs.
- Once downloaded, you should ask the {ref}`role_system_manager` to send you a secure email with the decryption key.

```{caution}
Please check with your {ref}`role_system_manager` to ensure that they use an encryption method that you are able to decrypt.
```

(role_data_provider_representative_egress_physical)=

### Request a physical disk

Alternatively, you can request your data on a physical disk/USB stick.
Check whether your {ref}`role_system_manager` is happy to do this for you.

- Request delivery/courier of the device from the hosting institution.
- Once received, you should ask the {ref}`role_system_manager` to send you a secure email with the decryption key.

```{caution}
Please check with your {ref}`role_system_manager` to ensure that they use an encryption method that you are able to decrypt.
```
