# Data ingress

Data ingress is the process of bringing sensitive data or software into the environment from an external source.
The policies defined here minimise the number of people who have access to restricted information before it is in the Environment.
Datasets must only be transferred from the {ref}`role_data_provider_representative` after an initial classification has been completed and the data sharing agreement executed.

Several methods of transfering sensitive data into the the Data Safe Haven are detailed below.
These are designed to minimise the risk of unauthorised access to the data.
In order to facilitate this, the {ref}`role_data_provider_representative` should take the following precautions:

- Use the most secure method of data transfer that your organisation can support.
- Once data transfer is complete, tell the {ref}`role_system_manager` so that they can revoke your access.

```{warning}
Since the tier of a secure environment cannot be changed after deployment it is important that all parties have reached consensus on the classification tier before starting data ingress.
```

## Categorise the data into one of the defined tiers

Remember that {ref}`policy_tier_0` is the least sensitive data tier and {ref}`policy_tier_4` the most sensitive.
If there are mixed data sensitivities in the complete data set then the whole data set must be assigned to the **most sensitive** data tier.

## Complete data sharing paperwork

The appropriate legal paperwork needs to be completed to ensure that a data sharing agreement is in place.
This step should also cover ethical considerations of sharing the data.
The project may need ethical approval from the appropriate body within the hosting organisation.
Permission to use the data (including {ref}`unconsented patient data <policy_unconsented_patient_data>`) should be obtained.
The data sharing paperwork must make very clear the tier to which the dataset has been assigned.

## Store the signed documents in a secure location

All documents detailed above should be available in a secure document store.
They certify that the users are allowed to have access to the specified data, and to process it in agreed ways.
A likely workflow is that the {ref}`role_project_manager` will place the authorised copy of the data sharing agreement in that location.
The version of the documents stored in the secure document store are the definitive ones.

## Transfer from data owner to the Data Safe Haven

Different processes should be followed depending on the tier to which the data has been assigned (as described in the {ref}`data classification process <policy_data_classification_process>`).
It is the responsibility of the {ref}`role_system_manager` conducting this step to ensure that they are following the appropriate process for the assigned data classification tier.

(policy_ingress_into_tier_3)=

### Transfer into Tier 3

There are several methods of transfering sensitive data to the Data Safe Haven which are listed below in order of preference.

```{tip}
When we refer to a **secure channel** below, we mean either a secure email service [certified](https://www.ncsc.gov.uk/information/commercial-product-assurance-cpa) by the UK National Cyber Security Centre (NCSC), a secure phone line or a secure in person conversation.
```

```{note}
When we refer to **authorised IP address(es)** below, we mean any IP address which has been provided by the {ref}`role_data_provider_representative` over a secure channel.
```

```{attention}
When we refer to **encryption** below, we are referring to any strong, modern encryption algorithm with a strong password. One possibility is to use a software package like [VeraCrypt](https://www.veracrypt.fr/en/Home.html).
```

#### Microsoft Azure Storage Explorer

[Azure Storage Explorer](https://azure.microsoft.com/en-us/features/storage-explorer/) is the most convenient way to safely transfer data.

- the {ref}`role_system_manager` creates a time-limited, write-only secure access token and sends this to the {ref}`role_data_provider_representative` over a secure channel.
- the {ref}`role_data_provider_representative` uses this token to securely upload their data directly from an authorised IP address to Azure storage.

#### SFTP/SCP

The next best option is to use `SFTP/SCP` if the {ref}`role_system_manager` is able to support this.

- the {ref}`role_system_manager` sets up a server and sends connection details to the {ref}`role_data_provider_representative` over a secure channel.
- the {ref}`role_data_provider_representative` uese these details to securely upload their **encrypted data** from an authorised IP address.
- the {ref}`role_data_provider_representative` sends the decryption key to the {ref}`role_system_manager` over a secure channel.
- the {ref}`role_system_manager` decrypts the data and moves it to Azure storage before securely deleting any intermediate files.

#### Website upload

- the {ref}`role_data_provider_representative` uploads their **encrypted data** to a file sharing site of their choice (for example `Dropbox`, `Google Drive`, `SharePoint`).
- the {ref}`role_data_provider_representative` sends the decryption key to the {ref}`role_system_manager` over a secure channel.
- the {ref}`role_system_manager` will then download and decrypt the data and move it to Azure storage before securely deleting any intermediate files.

#### Physical

- the {ref}`role_data_provider_representative` stores their **encrypted data** on a hard drive or USB stick.
- the {ref}`role_data_provider_representative` sends the decryption key to the {ref}`role_system_manager` over a secure channel.
- the hard drive should then be delivered or couriered to a **known individual** at the hosting organisation, authorised by the {ref}`role_system_manager`.
- the {ref}`role_system_manager` will then decrypt the data and move it to Azure storage before securely deleting any intermediate files.

```{danger}
The decryption key must not be delivered in the same physical package as the encrypted hard drive.
```

(policy_ingress_into_tier_2)=

### Transfer into Tier 2

For this category, the processes are be the same as for {ref}`Tier 3 <policy_ingress_into_tier_3>` above with the exception that pre-declaring an IP address for the `SFTP/SCP` option is not required.

(policy_ingress_into_tier_1)=

### Transfer into Tier 1

The same transfer processes as {ref}`Tier 2 <policy_ingress_into_tier_3>` is available to the data owners.
When using the website upload option, it is recommended but not required to encrypt the files.

```{danger}
Under no circumstance should sensitive data be sent via email, even if encrypted.
```

(policy_ingress_into_tier_0)=

### Transfer into Tier 0

This is publicly available, open data, and as such is likely to be hosted on a public website and can therefore simply be downloaded directly to the staging area.

## Test the integrity of the data

The {ref}`role_system_manager` attempt to verify that the files stored in the secure research environment are identical to those made available by the {ref}`role_data_provider_representative`.
This might involve:

- checking the number and names of files match
- checking file metadata matches
- checking that file sizes match
- checking that file hashes match

An integrity verification report should be generated by the {ref}`role_system_manager` which contains the file hashes, sizes and metadata.
This report should be stored together with the data sharing paperwork.
Any changes in the data should be versioned and an updated report generated.
