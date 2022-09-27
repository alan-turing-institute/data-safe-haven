(administrator_manage_data)=

# Managing data ingress and egress

```{important}
This document assumes that you already have access to a {ref}`Safe Haven Management (SHM) environment <deploy_shm>` and one or more {ref}`Secure Research Environments (SREs) <deploy_sre>` that are linked to it.
```

(roles_system_manager_data_ingress)=

## Data Ingress

It is the data provider's responsibility to upload the data required by the safe haven.

```{important}
Any data ingress must be signed off by the {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` (if applicable).
```

The following steps show how to generate a temporary write-only upload token that can be securely sent to the data provider, enabling them to upload the data:

- In the Azure portal select `Subscriptions` then navigate to the subscription containing the relevant SHM
- Search for the resource group: `RG_SHM_<SHM ID>_PERSISTENT_DATA`, then click through to the storage account called: `<SHM ID><SRE ID>data<storage suffix>` (where `<storage suffix>` is a random string)
- Click `Networking` under `Settings` and paste the data provider's IP address as one of those allowed under the `Firewall` header, then hit the save icon in the top left
- From the `Overview` tab, click the link to `Containers` (in the middle of the page)
- Click `ingress`
- Click `Shared access signature` under `Settings` and do the following:
  - Under `Permissions`, check these boxes:
    - `Write`
    - `List`
  - Set a 24 hour time window in the `Start and expiry date/time` (or an appropriate length of time)
  - Leave everything else as default and click `Generate SAS token and URL`
  - Copy the `Blob SAS URL`
- Send the `Blob SAS URL` to the data provider via secure email (for example, you could use the [Egress secure email](https://www.egress.com/) service)
- The data provider should now be able to upload data by following {ref}`these instructions <process_data_ingress>`
- You can validate successful data ingress by logging into the SRD for the SRE and checking the `/data` volume, where you should be able to view the data that the data provider has uploaded

(roles_system_manager_software_ingress)=

## Software Ingress

Software ingress is performed in a similar manner to data.

```{important}
Software ingress must go through the same approval process as is the case for data ingress, including sign-off from the {ref}`role_data_provider_representative`, {ref}`role_investigator` and {ref}`role_referee` (if applicable).
```

- Follow the same steps as for {ref}`data ingress <roles_system_manager_data_ingress>` above to provide temporary write access, but set the time window for the SAS token to a shorter period (e.g. several hours)
- Share the token with the {ref}`role_investigator`, so they can install software within the time window
- The {ref}`role_investigator` can perform software ingress via `Azure Storage Explorer` (for instance as a zip file), by following the same instructions as {ref}`the data provider <process_data_ingress>`

(roles_system_manager_data_egress)=

## Data egress

- In the Azure portal select `Subscriptions` then navigate to the subscription containing the relevant SHM
- Search for the resource group: `RG_SHM_<SHM ID>_PERSISTENT_DATA`, then click through to the storage account called: `<SHM ID><SRE ID>data<storage suffix>` (where `<storage suffix>` is a random string)
- Click `Networking` under `Settings` to check the list of pre-approved IP addresses allowed under the `Firewall` header and check your own IP address to ensure you are connecting from one of these
- Click `Containers` under `Data storage`
- Click `egress`
- Click `Shared access signature` under `Settings` and do the following:
  - Under `Permissions`, check these boxes:
    - `Read`
    - `List`
  - Set a time window in the `Start and expiry date/time` that gives you enough time to extract the data
  - Leave everything else as default click `Generate SAS token and URL`

    ```{image} administrator_guide/read_only_sas_token.png
    :alt: Read-only SAS token
    :align: center
    ```

  - Leave this portal window open and move to the next step
- Open `Azure Storage Explorer` ([download](https://azure.microsoft.com/en-us/products/storage/storage-explorer/) it if you don't have it)
- Click the socket image on the left hand side

  ```{image} ../data_provider_representative/azure_storage_explorer_connect.png
  :alt: Azure Storage Explorer connection
  :align: center
  ```

- On `Select Resource`, choose `Blob container`
- On `Select Connection Method`, choose `Shared access signature URL (SAS)` and hit `Next`

  ```{image} administrator_guide/connect_azure_storage.png
  :alt: Connect with SAS token
  :align: center
  ```

- On `Enter Connection Info`:
  - Set the `Display name` to "egress" (or choose an informative name)
  - Copy the `Blob SAS URL` from your Azure portal session into the `Blob container SAS URL` box and hit `Next`
- On the `Summary` page, hit `Connect`
- On the left hand side, the connection should show up under `Local & Attached > Storage Accounts > (Attached Containers) > Blob Containers > ingress (SAS)`
- You should now be able to securely download the data from the Safe Haven's output volume by highlighting the relevant file(s) and hitting the `Download` button

### The output volume

Once you have set up the egress connection in `Azure Storage Explorer`, you should be able to view data from the **output volume**, a read-write area intended for the extraction of results, such as figures for publication.
On the SRD, this volume is `/output` and is shared between all SRDs in an SRE.
For more info on shared SRE storage volumes, consult the {ref}`Safe Haven User Guide <role_researcher_user_guide_shared_storage>`.

## {{file_cabinet}} Backup

### {{card_file_box}} Restoring blobs

Blob containers in backed up storage accounts are protected by [operational backup](https://learn.microsoft.com/en-us/azure/backup/blob-backup-overview#how-operational-backup-works).
It is possible to restore the state of the blobs to an earlier point in time, up to twelve weeks in the past.

The blob containers covered by the protection for each SRE are the

- ingress container (mounted at `/data`)
- egress container (mounted at `/output`)
- backup container (mounted at `/backup`)

To restore these containers to a previous point in time:

```{important}
Blobs are restored 'in place'.
The current state will be overwritten by the point which you restore to.
```

- In the Azure portal select `Subscriptions` then navigate to the subscription containing the relevant SRE
- Search for the resource group: `RG_SHM_<SHM ID>_SRE_<SRE ID>_BACKUP`, then click on the storage account called: `bv-<shm id>-sre-<sre id>`
- Click `Backup instances` under `Manage` in the left-hand menu
- Ensure that the `Datasource type` filter is set to `Azure Blobs (Azure Storage)`

  ```{image} administrator_guide/backup_instances_blobs.png
  :alt: Selecting blob backup instances
  :align: center
  ```

- Click on the storage-account backup instance
- Select a point in the past to restore to and click `Restore`

  ```{image} administrator_guide/backup_select_restore_time_blobs.png
  :alt: Selecting blob backup restore point
  :align: center
  ```

- Click on `Next: Restore Parameters`
- You can now choose whether to restore all, or a subset of the containers. In the example below the 'egress' and 'backup' containers are selected
- Click on `Validate`

  ```{image} administrator_guide/backup_select_containers_validate_blobs.png
  :alt: Selecting blob containers to restore and validating
  :align: center
  ```

- Click on `Next: Review + restore`
- Click on `Restore`

### {{optical_disk}} Restoring disks

Backed up disks have incremental snapshots taken daily.
These snapshots are stored in the backup resource group,`RG_SHM_<SHM ID>_SRE_<SRE ID>_BACKUP`.

The disks covered by the protection for each SRE are the

- GitLab data disk
- CodiMD data disk
- CoCalc data disk
- PostgreSQL data disk
- MSSQL data disk

To restore a disk:

```{important}
Restoring a disk creates a new disk object from the incremental snapshots.
You will need to specify where to create the disk and its name.
You will also need to attach the disk to any virtual machines which should use
it and enroll the new disk into the backup system.
```

- In the Azure portal select `Subscriptions` then navigate to the subscription containing the relevant SRE
- Search for the resource group: `RG_SHM_<SHM ID>_SRE_<SRE ID>_BACKUP`, then click on the storage account called: `bv-<shm id>-sre-<sre id>
- Click `Backup instances` under `Manage` in the left-hand menu
- Ensure that the `Datasource type` filter is set to `Azure Disks`

  ```{image} administrator_guide/backup_instances_disks.png
  :alt: Selecting disk backup instances
  :align: center
  ```

- Click on the disk to restore
- Click `Restore`
- Click `Select restore point` to choose which snapshot to revert to and click `Select`. By default only snapshots from the last 30 days are displayed but this can be adjusted
- Click `Next: Restore Parameters`
- Enter the subscription and resource group in which to create the new disk; these should match the original disk
- Enter a name for the new disk and click `Validate`

  ```{image} administrator_guide/backup_select_snapshot_validate_disks.png
  :alt: Configuring and validating disk backup
  :align: center
  ```

- Click on `Next: Review + restore`
- Click on `Restore`
- Wait for the restoration to finish. You can monitor the progress on the backup instance page on the Azure portal

  ```{image} administrator_guide/backup_progress_disk_1.png
  :align: center
  ```

  ```{image} administrator_guide/backup_progress_disk_2.png
  :align: center
  ```

  ```{image} administrator_guide/backup_progress_disk_3.png
  :align: center
  ```

- Navigate to the resource group where the new disk has been created
- Select the virtual machine that the old disk is attached to and click `Disks` in the left-hand menu
- Take note of the old disks `LUN`
- Remove the old disk by clicking the 'X' at the right-hand side of the disk table
- Click `Save`
- Click `Attach existing disks` and select the disk you restored
- Ensure the restored disk has the same 'LUN' as the old disk
- Click `Save`

  ```{image} administrator_guide/backup_swap_disk_before.png
  :alt: The state before swapping in the restored disk
  :align: center
  ```

  ```{image} administrator_guide/backup_swap_disk_after.png
  :alt: The state after swapping in the restored disk
  :align: center
  ```

- Restart the virtual machine

### {{optical_disk}} Enrolling restored disks for backup

On your **deployment machine**.

- Ensure you have the same version of the Data Safe Haven repository as was used by your deployment team
- Open a `Powershell` terminal and navigate to the `deployment/administration` directory within the Data Safe Haven repository
- Ensure you are logged into `Azure` within `Powershell` using the command: `Connect-AzAccount`. This command will give you a URL and a short alphanumeric code. You will need to visit that URL in a web browser and enter the code
- NB. If your account is a guest in additional Azure tenants, you may need to add the `-Tenant <Tenant ID>` flag, where `<Tenant ID>` is the ID of the Azure tenant you want to deploy into
- Note the name of the restored disk and the name of the resource group it belongs to
- Run the following script subsituting <resource group name> and <disk name> with the names of the resource group and disk respectively:

  ```powershell
  ./SRE_Enroll_Disk_Backup.ps1 -shmId <SHM ID> -sreId <SRE ID> -resourceGroup
  <resource group name> -diskName <disk name>
  ```

## {{package}} Updating allowed repository packages

For a {ref}`policy_tier_3` SRE, only the packages named in the allowlists at `environment_configs/package_lists/` can be installed by users.

To update the allowlists on an SHM, you should use the `SHM_Package_Repository_Update_Allowlists.ps1` script.

```powershell
PS> /deployment/administration/SHM_Package_Repository_Update_Allowlists.ps1 -shmId <SHM ID>
```

By default, this script will use the allowlists present in `environment_configs/package_lists/` but you may use the `-allowlistDirectory` option to specify another directory containing the allowlists.
It is assumed that the allowlists will have the same names as those in in `environment_configs/package_lists/`.
