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

- A [Microsoft Entra](https://learn.microsoft.com/en-us/entra/fundamentals/) tenant for managing your users
    - An account with [Global Administrator](https://learn.microsoft.com/en-us/entra/global-secure-access/reference-role-based-permissions#global-administrator) privileges on this tenant
- An Azure subscription where you will deploy your infrastructure
    - An account with at least [Contributor](https://learn.microsoft.com/en-us/azure/role-based-access-control/built-in-roles/general#contributor) permissions on this subscription

## Deployment

Before deploying the Safe Haven Management (SHM) infrastructure you need to decide on a few parameters:

**entra_tenant_id**
: Tenant ID for the Entra ID used to manage TRE users

    :::{admonition} How to find your Microsoft Entra Tenant ID
    :class: dropdown hint

    - Go to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
    - Click on your username / profile icon in the top right
    - Click **{guilabel}`Switch directory`** in the dropdown menu
    - Ensure that you have selected the directory you chose above
    - Browse to **{menuselection}`Identity --> Overview`** from the menu on the left side.
    - Take note of the `Tenant ID`

    :::

**fqdn**
: Domain name that your TRE users will belong to.

  :::{hint}
  Use a domain that you own! If you use _e.g._ `example.org` here your users will be given usernames like `ada.lovelace@example.org`
  :::

**location**
: Azure location where you want your resources deployed.

  :::{hint}
  Use the short name without spaces, _e.g._ **uksouth** not **UK South**
  :::

Once you've decided on these, run the following command: [approx 5 minutes]:

:::{code} shell
$ dsh shm deploy --entra-tenant-id YOUR_ENTRA_TENANT_ID \
                 --fqdn YOUR_DOMAIN_NAME \
                 --location YOUR_LOCATION
:::

:::{note}
You will be prompted to log in to the Azure CLI and to the Graph API.

- Azure CLI: use your **infrastructure** user credentials
- Graph API: use your **Entra tenant** administrator credentials

:::

:::{important}
You may be asked to delegate your domain name to Azure. To do this, you'll need to know details about the parent domain. For example, if you are deploying to `dsh.example.com` then the parent name is `example.com`.

- Follow [this tutorial](https://learn.microsoft.com/en-us/azure/dns/dns-delegate-domain-azure-dns#delegate-the-domain) if the parent domain is hosted **outside Azure**
- Follow [this tutorial](https://learn.microsoft.com/en-us/azure/dns/tutorial-public-dns-zones-child#verify-the-child-dns-zone) if the parent domain is hosted **in Azure**

:::
