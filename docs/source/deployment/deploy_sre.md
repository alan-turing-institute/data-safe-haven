(deploy_sre)=

# Deploy a Secure Research Environment

These instructions will deploy a new Secure Research Environment (SRE).

::::{note}
As the Basic Application Gateway is still in preview, you will need to run the following commands once per subscription:

:::{code} shell
$ az feature register --name "AllowApplicationGatewayBasicSku" \
                      --namespace "Microsoft.Network" \
                      --subscription NAME_OR_ID_OF_YOUR_SUBSCRIPTION
$ az provider register --name Microsoft.Network
:::

::::

## Configuration

Each project will have its own dedicated SRE.

- Create a configuration file (optionally starting from one of our standard {ref}`policy_classification_sensitivity_tiers`)

::::{admonition} EITHER start from a blank template
:class: dropdown note

:::{code} shell
$ dsh config template --file PATH_YOU_WANT_TO_SAVE_YOUR_YAML_FILE_TO
:::
::::

::::{admonition} OR start from a predefined tier
:class: dropdown note

:::{code} shell
$ dsh config template --file PATH_YOU_WANT_TO_SAVE_YOUR_YAML_FILE_TO \
                      --tier TIER_YOU_WANT_TO_USE
:::
::::

- Edit this file in your favourite text editor, replacing the placeholder text with appropriate values for your setup.

::::{admonition} Example YAML configuration file
:class: dropdown tip

:::{code} yaml
azure:
  subscription_id: # ID of the Azure subscription that the TRE will be deployed to
  tenant_id: # Home tenant for the Azure account used to deploy infrastructure: `az account show`
description: # A free-text description of your SRE deployment
dockerhub:
  access_token: # The password or personal access token for your Docker Hub account. We strongly recommend using a Personal Access Token with permissions set to Public Repo Read-only
  username: # Your Docker Hub account name
name: # A name for your SRE deployment containing only letters, numbers, hyphens and underscores
sre:
  admin_email_address: # Email address shared by all administrators
  admin_ip_addresses: # List of IP addresses belonging to administrators
  data_provider_ip_addresses: # List of IP addresses belonging to data providers
  databases: # List of database systems to deploy
  remote_desktop:
    allow_copy: # True/False: whether to allow copying text out of the environment
    allow_paste: # True/False: whether to allow pasting text into the environment
  research_user_ip_addresses: # List of IP addresses belonging to users
  software_packages: # Which Python/R packages to allow users to install: [any/pre-approved/none]
  timezone: # Timezone in pytz format (eg. Europe/London)
  workspace_skus: # List of Azure VM SKUs that will be used for data analysis.
:::

::::

:::{hint}
See [here](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/) for a full list of valid Azure VM SKUs.
:::

:::{important}
All VM SKUs you deploy must support premium SSDs.

- SKUs that support premium SSDs have a lower case 's' in their name.
- See [here](https://learn.microsoft.com/en-us/azure/virtual-machines/vm-naming-conventions) for a full naming convention explanation.
- See [here](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-types#premium-ssds) for more details on premium SSD support.

:::

:::{important}
All VM SKUs you deploy must have CPUs with the `x86_64` architecture.

- SKUs with a lower case 'p' in their name have the ARM architecture and should not be used.
- See [here](https://learn.microsoft.com/en-us/azure/virtual-machines/vm-naming-conventions) for a full naming convention explanation.

:::

:::{important}
The antivirus process running on each workspace consumes around 1.3 GiB at idle.
This usage will roughly double for a short period each day while its database is updated.

You should take this into account when choosing a VM size and pick an SKU with enough memory overhead for your workload and the antivirus service.
:::

:::{important}
Only GPUs supported by CUDA and the Nvidia GPU drivers can be used.
['N' series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/overview#gpu-accelerated) SKUs feature GPUs.
The NC and ND families are recommended as they feature GPUs designed for general purpose computation rather than graphics processing.

There is no key to distinguish SKUs with Nvidia GPUs, however newer SKUs contain the name of the accelerator.
:::

:::{hint}
Picking a good VM size depends on a lot of variables.
You should think about your expected use case and what kind of resources you need.

As some general recommendations,

- For general purpose use, the D family gives decent performance and a good balance of CPU and memory.
  The [Dsv6 series](https://learn.microsoft.com/en-us/azure/virtual-machines/sizes/general-purpose/dsv6-series#sizes-in-series) is a good starting point and can be scaled from 2 CPUs and 8 GB RAM to 128 CPUs and 512 GB RAM.
    - `Standard_D8s_v6` should give reasonable performance for a single concurrent user.
- For GPU accelerated work, the NC family provides Nvidia GPUs and a good balance of CPU and memory.
  In order of increasing throughput, the `NCv3` series features Nvidia V100 GPUs, the `NC_A100_v4` series features Nvidia A100 GPUs, and the `NCads_H100_v5` series features Nvidia H100 GPUs.
    - `Stanard_NC6s_v3` should give reasonable performance for a single concurrent user with AI/ML workloads.
    Scaling up in the same series (for example `Standard_NC12s_v3`) gives more accelerators of the same type.
    Alternatively a series with more recent GPUs should give better performance.

:::

## Upload the configuration file

- Upload the config to Azure. This will validate your file and report any problems.

:::{code} shell
$ dsh config upload PATH_TO_YOUR_EDITED_YAML_FILE
:::

:::{hint}
If you want to make changes to the config, edit this file and then run `dsh config upload` again
:::

## Deployment

- Deploy each SRE individually [approx 30 minutes]:

:::{code} shell
$ dsh sre deploy YOUR_SRE_NAME
:::

::::{important}
After deployment, you may need to manually ensure that backups function.

- In the Azure Portal, navigate to the resource group for the SRE: **shm-_SHM\_NAME_-sre-_SRE\_NAME_-rg**
- Navigate to the backup vault for the SRE: **shm-_SHM\_NAME_-sre-_SRE\_NAME_-bv-backup**
- From the side menu, select **{menuselection}`Manage --> Backup Instances`**
- Change **Datasource type** to  **Azure Blobs (Azure Storage)**
- Select the **BlobBackupSensitiveData** instance

If you see the message **Fix protection error for the backup instance**, as pictured below, then click the **{guilabel}`Fix protection error`** button.

:::{image} images/backup_fix_protection_error.png
:alt: Fix protection error for the backup instance
:align: center
:::
::::
