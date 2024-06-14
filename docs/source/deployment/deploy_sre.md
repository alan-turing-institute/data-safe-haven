(deploy_sre)=

# Deploy a Secure Research Environment (SRE)

## Configuration

Each project will have its own dedicated Secure Research Environment (SRE).

- Create a configuration file

```console
> dsh config template-sre --file config.yaml
```

- Edit this file in your favourite text editor, replacing the placeholder text with appropriate values for your setup.


## Upload the configuration file

- Upload the config to Azure. This will validate your file and report any problems.

```{code} shell
$ dsh config upload-sre config.yaml
```

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
$ dsh sre deploy <name of your SRE>
```
