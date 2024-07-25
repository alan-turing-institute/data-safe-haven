(deploy_shm)=

# Deploy a Safe Haven Management Environment (SHM)

These instructions will deploy a new Safe Haven Management Environment (SHM).
This is required to manage your Secure Research Environments (SREs) and **must be** deployed before you create any SREs.

:::{note}
A single SHM can manage all your SREs.
However, you may choose to use multiple SHMs if, for example, you want to separate production and development environments.
:::

## Requirements

- A [Microsoft Entra](https://learn.microsoft.com/en-us/entra/fundamentals/) tenant
- An account with [Global Administrator](https://learn.microsoft.com/en-us/entra/global-secure-access/reference-role-based-permissions#global-administrator) privileges on this tenant
- An account with at least [Contributor](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#contributor) permissions on the Azure subscription where you will deploy your infrastructure

:::{hint}
We suggest using a dedicated Microsoft Entra tenant for your DSH deployment, but this is not a requirement.

We recommend using a separate tenants for your users and your infrastructure subscriptions, but this is not a requirement.
:::

:::{admonition} How to deploy a new tenant
:class: dropdown hint
Follow the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/create-new-tenant).

- set the `Organisation Name` to something appropriate for your deployment (e.g. `Contoso Production Safe Haven`)
- set the `Initial Domain Name` to the lower-case version of the `Organisation Name` with spaces and special characters removed (e.g. `contosoproductionsafehaven`)
- set the `Country or Region` to whichever country is appropriate for your deployment (e.g. `United Kingdom`)
:::

## Deployment

Before deploying the Safe Haven Management (SHM) infrastructure you need to decide on a few parameters:

- `entra_tenant_id`: Tenant ID for the Entra ID used to manage TRE users

    :::{admonition} How to find your Microsoft Entra Tenant ID
    :class: dropdown hint

    - Go to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
    - Click on your username / profile icon in the top right and select `Switch directory`
    - Ensure that you have selected the directory you chose above
    - Browse to **Identity > Overview** from the menu on the left side.
    - Take note of the `Tenant ID`
    :::


- `fqdn`: Domain you want your users to belong to and to access your TRE from
- `location`: Azure location where you want your resources deployed

Once you've decided on these, run the following command: [approx 5 minutes]:

```{code} shell
$ dsh shm deploy --entra-tenant-id <Entra tenant ID> --fqdn <fully-qualified domain name> --location <location>
```

:::{note}
You will be prompted to log in to the Azure CLI and to the Graph API.
- Azure CLI: use your **infrastructure** user credentials
- Graph API: use your **Entra tenant** administrator credentials
:::

:::{important}
You may be asked to delegate your domain name to Azure. To do this, you'll need to know details about the parent domain. For example, if you are deploying to `dsh.example.com` then the parent name is `example.com`.

- Follow [this tutorial](https://learn.microsoft.com/en-us/azure/dns/dns-delegate-domain-azure-dns#delegate-the-domain) if the parent domain is hosted outside Azure
- Follow [this tutorial](https://learn.microsoft.com/en-us/azure/dns/tutorial-public-dns-zones-child#verify-the-child-dns-zone) if the parent domain is hosted in Azure

:::
