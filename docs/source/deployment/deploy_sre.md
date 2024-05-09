(deploy_sre)=

# Deploy a Secure Research Environment (SRE)

## Configuration

Each project will have its own dedicated Secure Research Environment (SRE).

Make sure that your config file contains one or more SRE sections.

:::{tip}
You can check this by running: `dsh config show` and looking at the `sres` section.
:::

## Requirements

:::{important}
As private endpoints for flexible PostgreSQL are still in preview, the following command is currently needed:

```{code} shell
$ az feature register --name "enablePrivateEndpoint" --namespace "Microsoft.DBforPostgreSQL"
```

:::

## Deployment

- Deploy each SRE individually [approx 30 minutes]:

```{code} shell
$ dsh deploy sre <name of your SRE>
```
