(setup_context)=

# Set up context

The 'context' contains some basic metadata about your TRE deployment.
It defines the name of your TRE and the subscription where the supporting resources should be deployed.

:::{important}
The context **must** be setup before any TRE components can be deployed.
:::

## Configuration

A local context configuration file (`context.yaml`) holds the information necessary to find and access a context.

:::{note}
You can specify the directory where your context configuration (`context.yaml`) is stored by setting the environment variable `DSH_CONFIG_DIRECTORY`.
:::

## Creating a context

- You will need to provide some options to set up your DSH context. You can see what these are by running the following:

:::{code} shell
$ dsh context add --help
:::

- Run a command like the following to create your local context file.

:::{code} shell
$ dsh context add --admin-group-name AZURE_SECURITY_GROUP_CONTAINING_ALL_ADMINISTRATORS \
                  --name NAME_WITH_ONLY_LETTERS_NUMBERS_AND_UNDERSCORES \
                  --description HUMAN_FRIENDLY_DESCRIPTION_OF_YOUR_TRE \
                  --subscription-name AZURE_SUBSCRIPTION_NAME
:::

:::{note}
If you have multiple contexts defined, you can select which context you want to use with `dsh context switch CONTEXT_NAME`.
:::
