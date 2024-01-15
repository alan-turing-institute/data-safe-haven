# Requirements

Install the following requirements before starting

- [Poetry](https://python-poetry.org/docs/#installation)
- [Pulumi](https://www.pulumi.com/docs/get-started/install/)

## Deploying a Data Safe Haven

- Run the following to initialise the deployment [approx 5 minutes]:

```console
> dsh context add ...
> dsh context create
```

- Create the configuration

```console
> dsh config template --file config.yaml
> vim config.yaml
> dsh config upload config.yaml
```

- Next deploy the Safe Haven Management (SHM) infrastructure [approx 30 minutes]:

```console
> dsh deploy shm
```

You will be prompted for various settings.
Run `dsh deploy shm -h` to see the necessary command line flags and provide them as arguments.

- Add one or more users from a CSV file with columns named (`GivenName`, `Surname`, `Phone`, `Email`, `CountryCode`).
  Note that the phone number must be in full international format.
  Note that the country code is the two letter `ISO 3166-1 Alpha-2` code.

```console
> dsh admin add-users <my CSV users file>
```

- Next deploy the infrastructure for one or more Secure Research Environments (SREs) [approx 30 minutes]:

```console
> dsh deploy sre <SRE name>
```

You will be prompted for various settings.
Run `dsh deploy sre -h` to see the necessary command line flags and provide them as arguments.

- Next add one or more existing users to your SRE

```console
> dsh admin register-users -s <SRE name> <username1> <username2>
```

where you must specify the usernames for each user you want to add to this SRE

## Administering a Data Safe Haven

- Run the following to list the currently available users

```console
> dsh admin list-users
```

## Removing a deployed Data Safe Haven

- Run the following if you want to teardown a deployed SRE:

```console
> dsh teardown sre <SRE name>
```

- Run the following if you want to teardown the deployed SHM:

```console
> dsh teardown shm
```

- Run the following if you want to teardown the deployed Data Safe Haven context:

```console
> dsh context teardown
```

## Code structure

- administration
    - this is where we keep utility commands for adminstrators of a deployed DSH
    - eg. "add a user"; "remove a user from an SRE"
- context
    - in order to use the Pulumi Azure backend we need a KeyVault, Identity and Storage Account
    - this code deploys those resources to bootstrap the rest of the Pulumi-based code
    - the storage account is also used to store configuration, so that it can be shared by admins
- commands
    - the main `dsh` command line entrypoint lives in `cli.py`
    - the subsidiary `typer` command line entrypoints (eg. `dsh deploy shm`) live here
- config
    - serialises and deserialises a config file from Azure
    - `context_settings` manages basic settings related to the context: arguably this could/should live in `context`
- exceptions
    - definitions of a Python exception hierarchy
- external
    - Python wrappers around:
        - APIs: Azure Python SDK, Azure CLI, Graph API
        - Azure interfaces: CLI authentication, container instances, fileshares, available IP addresses in a subnet, databases
        - Utility for running scripts on databases
- functions
    - Various functions that don't fit anywhere else
    - string manipulation, type conversions, validators, lists of allowed external FQDNs
- infrastructure
    - Management of the Pulumi stack, which handles passing the correct backend options
    - common
        - common Pulumi transformations, enums and IP address ranges
    - components
        - composite
            - a logical group of existing Pulumi components that is used in several places
        - dynamic
            - a custom component to implement some functionality that is not natively supported
        - wrapped
            - thin wrappers around Pulumi resources to expose additional methods/attributes
    - stacks
        - definitions of the `shm` and `sre` stacks
- provisioning
    - all configuration options that is currently done outside Pulumi
    - eg. Initialise the Guacamole database, reboot some VMs, create security groups on domain controller
    - in the future this could be replaced by better orchestration options (eg. Ansible) or moved into Pulumi
- resources
    - configuration files and templates used by Pulumi (e.g. cloud-init configs, Caddyfiles etc.)
- utility
    - Useful classes: logging, file reading, types
