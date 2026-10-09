# Managing data ingress and egress

## Data ingress

It is the {ref}`role_data_provider_representative`'s responsibility to upload the data required by the safe haven.

You need to generate a temporary, write-only upload token that can be securely sent to the {ref}`role_data_provider_representative`, enabling them to upload the data.

### Using `dsh` (recommended)

Run {typer}`dsh create-sas` with the data provider's IP address and the time window for the upload:

:::{code} shell
$ dsh create-sas YOUR_SRE_NAME --container ingress --ip DATA_PROVIDER_IP_ADDRESS --end END_DATETIME
:::

- `--ip` accepts a single IPv4 address or a CIDR range
- `--start` and `--end` accept dates (`2026-10-08`) or datetimes (`2026-10-08T09:00`) in UTC. `--start` defaults to now and `--end` can be at most 7 days from now.
- Instead of `--end`, you can use `--hours` to set how many hours after the start time the URL expires, e.g. `--hours 24`. Use either `--end` or `--hours`, not both.

The command adds the IP address to the firewall of the storage account ending with `sensitivedata` and prints a **Blob SAS URL** with write and list permissions on the **ingress** container.
The URL is only valid for the given IP address and time window.

:::{note}
If the IP address is not in the `data_provider_ip_addresses` list of your SRE configuration, the next `dsh sre deploy` will remove it from the firewall.
:::

Send the **Blob SAS URL** to the data provider through a secure channel.
Then validate the upload and complete the follow-up tasks, as described in the last steps of the Azure portal route below.

### Using the Azure portal

Alternatively, follow these steps:

- In the Azure portal select **Subscriptions** then navigate to the subscription containing the relevant SHM
- Search for the resource group: `shm-<YOUR_SHM_NAME>-sre-<YOUR_SRE_NAME>-rg`, then click through to the storage account ending with `sensitivedata`
- Browse to **{menuselection}`Security + networking --> Networking`** and ensure that the data provider's IP address is one of those allowed under the **Firewall** header
    - If it's not listed there are two possible approaches to take:
        - Either: directly add the IP address on the **Networking** page in Azure.
        - Or: use `dsh` to modify and redeploy the configuration with the IP address added to the `data_provider_ip_addresses` list.
           See the {ref}`ingress_egress_update_ip_address_and_redeploy` section below for details.
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

      :::{image} ingress_token_write_only.png
      :alt: write-only SAS token
      :align: center
      :::

- Send the **Blob SAS URL** to the data provider through a secure channel
- The data provider should now be able to upload data
- Validate successful data ingress
    - Browse to **{menuselection}`Data storage --> Containers`** (in the middle of the page)
    - Select the **ingress** container and ensure that the uploaded files are present
- Once the user has uploaded the data, or the ingress time window has expired, the IP address must be removed from the firewall rules.
  See the {ref}`ingress_egress_follow_up_tasks` section below for details.

## Data egress

:::{important}
Assessment of output must be completed **before** an egress link is created.
Outputs are potentially sensitive, and so an appropriate process must be applied to ensure that they are suitable for egress.
:::

The {ref}`role_system_manager` creates a time-limited and IP restricted link to remove data from the environment.

- In the Azure portal select **Subscriptions** then navigate to the subscription containing the relevant SHM
- Search for the resource group: `shm-<YOUR_SHM_NAME>-sre-<YOUR_SRE_NAME>-rg`, then click through to the storage account ending with `sensitivedata`
- Browse to **{menuselection}`Security + networking --> Networking`** and check the list of pre-approved IP addresses allowed under the **Firewall** header
    - Ensure that the IP address of the person to receive the outputs is listed. If it's not listed there are two possible approaches to take:
        - Either: directly add the IP address on the **Networking** page in Azure.
        - Or: use `dsh` to modify and redeploy the configuration with the IP address added to the `data_provider_ip_addresses` list.
           See the {ref}`ingress_egress_update_ip_address_and_redeploy` section below for details.
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

      :::{image} egress_token_read_only.png
      :alt: Read-only SAS token
      :align: center
      :::

- Send the **Blob SAS URL** to the relevant person through a secure channel
- The appropriate person should now be able to download data
- Once the user has downloaded the data, or the egress time window has expired, the IP address must be removed from the firewall rules.
  See the {ref}`ingress_egress_follow_up_tasks` section below for details.

(ingress_egress_update_ip_address_and_redeploy)=

## Update IP address and redeploy

For both data ingress and egress the firewall IP addresses must be updated to allow access to the data.
This can be done either through the Azure Portal or by redeploying using the `dsh` command line tool.
The high-level steps for redeploy using `dsh` are as follows for reference.

- Use `dsh config show` to download the existing configuration for the SRE in YAML format.
- Modify the `data_provider_ip_addresses` list in the downloaded file using your favourite text editor to either add or remove the IP address as appropriate.
- Upload the configuration YAML file using `dsh`.
- Redeploy the SRE.

This translates into the following commands (where the `<sre-name>` should be adjusted as appropriate).

```sh
dsh config available
dsh config show <sre-name> --file sre-config.yaml
# Edit the sre-config.yaml file to add or remove the IP address
dsh config upload sre-config.yaml
dsh sre deploy <sre-name>
```

See the {ref}`deploy_sre` page for full redeployment details.

(ingress_egress_follow_up_tasks)=

## Follow-up tasks

Following data egress or ingress the IP address should be removed from the firewall rules to ensure the system remains secure.
This task should therefore be performed either after the user has completed the data upload or download, or once the SAS token has expired.
The approach taken should reflect the approach you used to add the IP address in the above instructions.

- If you added the IP address to the **Networking** page on the Azure Portal, you should remove it from the same list.
- If you used the `dsh` command line tool to redeploy the SRE, you should remove the IP address from the configuration and redeploy.
  See the section {ref}`ingress_egress_update_ip_address_and_redeploy` above for details.

## The output volume

Once you have set up the egress connection in Azure Storage Explorer, you should be able to view data from the **output volume**, a read-write area intended for the extraction of results, such as figures for publication.
On the workspaces, this volume is `/mnt/output` and is shared between all workspaces in an SRE.
For more information on shared SRE storage volumes, consult the {ref}`Safe Haven User Guide <role_researcher_shared_storage>`.
