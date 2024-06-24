(deploy_shm)=

# Deploy a Safe Haven Management Environment (SHM)

These instructions will deploy a new Safe Haven Management Environment (SHM).
This is required to manage your Secure Research Environments (SREs) and **must be** deployed before you create any SREs.

:::{note}
A single SHM can manage all your SREs.
However, you may choose to use multiple SHMs if, for example, you want to separate production and development environments.
:::

## Deployment

Before deploying the Safe Haven Management (SHM) infrastructure you need to decide on a few parameters:

- `entra_tenant_id`: Tenant ID for the Entra ID used to manage TRE users
- `fqdn`: Domain you want your users to belong to and to access your TRE from
- `location`: Azure location where you want your resources deployed

Once you've decided on these, run the following command: [approx 5 minutes]:

```{code} shell
$ dsh shm deploy --entra-tenant-id <Entra tenant ID>  --fqdn <fully-qualified domain name>  --location <location>
```

:::{important}
You may be asked to delegate your domain name to Azure. To do this, you'll need to know details about the parent domain. For example, if you are deploying to `dsh.example.com` then the parent name is `example.com`.

- Follow [this tutorial](https://learn.microsoft.com/en-us/azure/dns/dns-delegate-domain-azure-dns#delegate-the-domain) if the parent domain is hosted outside Azure
- Follow [this tutorial](https://learn.microsoft.com/en-us/azure/dns/tutorial-public-dns-zones-child#verify-the-child-dns-zone) if the parent domain is hosted in Azure

:::
