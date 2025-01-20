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
- The {typer}`dsh-config-template` command provides template configuration files

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
  location: # Azure location where SRE resources will be deployed
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
  allow_workspace_internet: # True/False: whether to allow outbound internet access from workspaces. WARNING setting this to True will allow data to be moved out of the SRE WITHOUT OVERSIGHT OR APPROVAL
  data_provider_ip_addresses: # List of IP addresses belonging to data providers
  databases: # List of database systems to deploy
  remote_desktop:
    allow_copy: # True/False: whether to allow copying text out of the environment
    allow_paste: # True/False: whether to allow pasting text into the environment
  research_user_ip_addresses:
    - # List of IP addresses belonging to users
    - # You can also use the tag 'Internet' instead of a list
  software_packages: # Which Python/R packages to allow users to install: [any/pre-approved/none]
  storage_quota_gb:
    home: # Total size in GiB across all home directories
    shared: #Total size in GiB for the shared directories
  timezone: # Timezone in pytz format (eg. Europe/London)
  workspace_skus: # List of Azure VM SKUs that will be used for data analysis.
:::

::::

### Configuration guidance

#### Choosing an Azure region

Some of the SRE resources are not available in all Azure regions.

- Workspace virtual machines use zone redundant storage managed disks which have [limited regional availability](https://learn.microsoft.com/en-us/azure/virtual-machines/disks-redundancy).
- Some shares mounted on workspace virtual machines require premium file shares which have [limited regional availability](https://learn.microsoft.com/en-us/azure/storage/files/redundancy-premium-file-shares).

:::{admonition} Supported Azure regions
:class: dropdown important

The regions which satisfy all requirements are,

- Australia East
- Brazil South
- Canada Central
- Central India
- China North 3
- East Asia
- East US
- East US 2
- France Central
- Germany West Central
- Israel Central
- Italy North
- Japan East
- Korea Central
- North Europe
- Norway East
- Poland Central
- Qatar Central
- South Africa North
- South Central US
- Southeast Asia
- Sweden Central
- Switzerland North
- UAE North
- UK South
- US Gov Virginia
- West Europe
- West US 2
- West US 3

:::

#### Choosing a VM SKU

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
    - `Standard_D8s_v5` should give reasonable performance for a single concurrent user.
- For GPU accelerated work, the NC family provides Nvidia GPUs and a good balance of CPU and memory.
  In order of increasing throughput, the `NCv3` series features Nvidia V100 GPUs, the `NC_A100_v4` series features Nvidia A100 GPUs, and the `NCads_H100_v5` series features Nvidia H100 GPUs.
    - `Stanard_NC6s_v3` should give reasonable performance for a single concurrent user with AI/ML workloads.
    Scaling up in the same series (for example `Standard_NC12s_v3`) gives more accelerators of the same type.
    Alternatively a series with more recent GPUs should give better performance.

:::

#### Copy and paste

The [Guacamole clipboard](https://guacamole.apache.org/doc/gug/using-guacamole.html#using-the-clipboard) provides an interface between the local clipboard and the clipboard on the remote workspaces.
Only text is allowed to be passed through the Guacamole clipboard.

The ability to copy and paste text to or from SRE workspaces via the Guacamole clipboard can be controlled with the DSH configuration parameters `allow_copy` and `allow_paste`.
`allow_copy` allows users to copy text from an SRE workspace to the Guacamole clipboard.
`allow_paste` allows users to paste text into an SRE workspace from the Guacamole clipboard.
These options have no impact on the ability to use copy and paste within a workspace.

The impact of setting each of these options is detailed in the following table.

<table class="table" id="id1">
    <caption><span class="caption-text">Configuration of copy and paste</span><a class="headerlink" href="#id1" title="Link to this table">#</a></caption>
    <thead>
      <tr class="row-odd" style="border-bottom:hidden">
        <th class="head" colspan = "2" style="text-align:center">Configuration setting</th>
        <th class="head" colspan = "4" style="text-align:center">Resulting behaviour</th>
      </tr>
      <tr class="row-odd">
        <th class="head"><tt>allow_copy</tt></th>
        <th class="head"><tt>allow_paste</tt></th>
        <th class="head">Copy/paste within workspace</th>
        <th class="head">Copy/paste between workspaces</th>
        <th class="head">Copy to local machine</th>
        <th class="head">Paste from local machine</th>
      </tr>
    </thead>
    <tbody>
      <tr class="row-even">
        <td>true</td>
        <td>true</td>
        <td>yes</td>
        <td>yes (via local machine)</td>
        <td>yes</td>
        <td>yes</td>
      </tr>
      <tr class="row-odd">
        <td>true</td>
        <td>false</td>
        <td>yes</td>
        <td>no</td>
        <td>yes</td>
        <td>no</td>
      </tr>
      <tr>
        <td>false</td>
        <td>true</td>
        <td>yes</td>
        <td>no</td>
        <td>no</td>
        <td>yes</td>
      </tr>
      <tr>
        <td>false</td>
        <td>false</td>
        <td>yes</td>
        <td>no</td>
        <td>no</td>
        <td>no</td>
      </tr>
    </tbody>
</table>

## Upload the configuration file

- Upload the config to Azure. This will validate your file and report any problems.

:::{code} shell
$ dsh config upload PATH_TO_YOUR_EDITED_YAML_FILE
:::

:::{hint}
If you want to make changes to the config, edit this file and then run `dsh config upload` again
:::

## Deployment

- Deploy each SRE individually using {typer}`dsh sre deploy` [approx 30 minutes]:

:::{code} shell
$ dsh sre deploy YOUR_SRE_NAME
:::
