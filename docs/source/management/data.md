# Managing data ingress and egress

## Data ingress

It is the {ref}`role_data_provider_representative`'s responsibility to upload the data required by the safe haven.

The following steps show how to generate a temporary, write-only upload token that can be securely sent to the {ref}`role_data_provider_representative`, enabling them to upload the data:

- In the Azure portal select **Subscriptions** then navigate to the subscription containing the relevant SHM
- Search for the resource group: `shm-<YOUR_SHM_NAME>-sre-<YOUR_SRE_NAME>-rg`, then click through to the storage account ending with `sensitivedata`
- Browse to **{menuselection}`Settings --> Networking`** and ensure that the data provider's IP address is one of those allowed under the **Firewall** header
    - If it is not listed, modify and reupload the SRE configuration and redeploy the SRE using the `dsh` CLI, as per {ref}`deploy_sre`
- Browse to **{menuselection}`Data storage --> Containers`** from the menu on the left hand side
- Click **ingress**
- Browse to **{menuselection}`Settings --> Shared access tokens`** and do the following:
    - Under **Signing method**, select **User delegation key**
    - Under **Permissions**, check these boxes:
        - **Write**
        - **List**
    - Set a 24 hour time window in the **Start and expiry date/time** (or an appropriate length of time)
    - Leave everything else as default and click **{guilabel}`Generate SAS token and URL`**
    - Copy the **Blob SAS URL**

      ```{image} ingress_token_write_only.png
      :alt: write-only SAS token
      :align: center
      ```

- Send the **Blob SAS URL** to the data provider through a secure channel
- The data provider should now be able to upload data
- Validate successful data ingress
    - Browse to **{menuselection}`Data storage --> Containers`** (in the middle of the page)
    - Select the **ingress** container and ensure that the uploaded files are present

## Data egress

```{important}
Assessment of output must be completed **before** an egress link is created.
Outputs are potentially sensitive, and so an appropriate process must be applied to ensure that they are suitable for egress.
```

The {ref}`role_system_manager` creates a time-limited and IP restricted link to remove data from the environment.

- In the Azure portal select **Subscriptions** then navigate to the subscription containing the relevant SHM
- Search for the resource group: `shm-<YOUR_SHM_NAME>-sre-<YOUR_SRE_NAME>-rg`, then click through to the storage account ending with `sensitivedata`
- Browse to **{menuselection}`Settings --> Networking`** and check the list of pre-approved IP addresses allowed under the **Firewall** header
    - Ensure that the IP address of the person to receive the outputs is listed
    - If it is not listed, modify and reupload the SRE configuration and redeploy the SRE using the `dsh` CLI, as per {ref}`deploy_sre`
- Browse to **{menuselection}`Data storage --> Containers`**
- Select the **egress** container
- Browse to **{menuselection}`Settings --> Shared access tokens`** and do the following:
    - Under **Signing method**, select **User delegation key**
    - Under **Permissions**, check these boxes:
        - **Read**
        - **List**
    - Set a time window in the **Start and expiry date/time** that gives enough time for the person who will perform the secure egress download to do so
    - Leave everything else as default and press **{guilabel}`Generate SAS token and URL`**
    - Copy the **Blob SAS URL**

      ```{image} egress_token_read_only.png
      :alt: Read-only SAS token
      :align: center
      ```

- Send the **Blob SAS URL** to the relevant person through a secure channel
- The appropriate person should now be able to download data

## The output volume

Once you have set up the egress connection in Azure Storage Explorer, you should be able to view data from the **output volume**, a read-write area intended for the extraction of results, such as figures for publication.
On the workspaces, this volume is `/mnt/output` and is shared between all workspaces in an SRE.
For more information on shared SRE storage volumes, consult the {ref}`Safe Haven User Guide <role_researcher_shared_storage>`.
