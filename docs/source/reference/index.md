# CLI Reference

:::{toctree}
:hidden:

config.md
context.md
users.md
pulumi.md
shm.md
sre.md
:::

A Data Safe Haven is managed using the `dsh` command line interface.
A full guide to the commands available for managing your Data Safe Haven is provided here.

The `dsh` commands are the entrypoint to the Data Safe Haven command line interface.
All commands begin with `dsh`.

:::{typer} data_safe_haven.commands.cli:application
:prog: dsh
:width: 65
:::

The subcommands can be used to manage various aspects of a Data Safe Haven deployment.
For further detail on each subcommand, navigate to the relevant page.

[Config](config.md)
: Management of the configuration files used to define SHMs and SREs

[Context](context.md)
: Manage DSH contexts, the groupings that encompass an SHM and its associated SREs

[Users](users.md)
: Management of users in Entra ID

[Pulumi](pulumi.md)
: An interface to the Pulumi command line interface

[shm](shm.md)
: Management of infrastructure for DSH Safe Haven Management environments

[sre](sre.md)
: Management of infrastructure for DSH Secure Research Environments
