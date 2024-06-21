(deploy_context)=

# Deploy the Data Safe Haven Context

The 'Context' is a collection of infrastructure, which _is not_ part of your TRE, but which is used to deploy and manage your TRE.
It contains, for example, storage for synchronising persistent configuration information.

:::{important}
The Context **must** be deployed before any other TRE components.
:::

## Configuration

A local context configuration file (`context.yaml`) holds the information necessary to find and access a context.

:::{note}
You can specify the directory where your context configuration (context.yaml) is stored by setting the environment variable `DSH_CONFIG_DIRECTORY`.
:::

## Creating a context

- You will need to provide some options to set up your DSH context. You can see what these are by running the following:

```{code} shell
$ dsh context add --help
```

- Run a command like the following to create your local context file.

```{code} shell
$ dsh context add --admin-group <group name> --location <location> --name <human friendly name> --subscription <Azure subscription name>
```

:::{note}
If you have multiple contexts defined, you can select which context you want to use with `dsh context switch <KEY>`.
:::
