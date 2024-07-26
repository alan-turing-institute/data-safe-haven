(deploy_shm)=

# Deploy the management environment

These instructions will deploy a new Safe Haven Management Environment (SHM).
This is required to manage your Secure Research Environments (SREs).

:::{important}
The SHM **must** be setup before any SREs can be deployed.
:::

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
:class: dropdown note
Follow the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/create-new-tenant).

- set the **Organisation Name** to something appropriate for your deployment (_e.g._ _Contoso Production Safe Haven_)
- set the **Initial Domain Name** to the lower-case version of the organisation name with spaces and special characters removed (_e.g._ _contosoproductionsafehaven_)
- set the **Country or Region** to whichever country is appropriate for your deployment (_e.g._ _United Kingdom_)

:::

## Deployment

Before deploying the Safe Haven Management (SHM) infrastructure you need to decide on a few parameters:

- `entra_tenant_id`: Tenant ID for the Entra ID used to manage TRE users
- `fqdn`: Fully-qualified domain you want your users to belong to and to access your TRE from
- `location`: Azure location where you want your resources deployed

:::{admonition} How to find your Microsoft Entra Tenant ID
:class: dropdown note

- Go to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Click on your username / profile icon in the top right and select `Switch directory`
- Ensure that you have selected the directory you chose above
- Browse to **{menuselection}`Identity --> Overview`** from the menu on the left side.
- Take note of the `Tenant ID`

:::

Once you've decided on these, run the following command: [approx 5 minutes]:

```{code} shell
$ dsh shm deploy --entra-tenant-id _YOUR_ENTRA_TENANT_ID_ --fqdn _YOUR_DOMAIN_NAME_ --location _YOUR_LOCATION_
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
