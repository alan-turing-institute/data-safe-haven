# Managing SREs

## List available SRE configurations and deployment status

- Use {typer}`dsh config available` to check what SRE configurations are available in the current context, and whether those SREs are deployed.

:::{code} shell
$ dsh config available
:::

will give output like the following

:::{code} shell
Available SRE configurations for context 'green':
┏━━━━━━━━━━━━━━┳━━━━━━━━━━┓
┃ SRE Name     ┃ Deployed ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━┩
│ emerald      │ x        │
│ jade         │          │
│ olive        │          │
└──────────────┴──────────┘
:::

## Remove a deployed Data Safe Haven

- Use {typer}`dsh sre teardown` to teardown a deployed SRE:

:::{code} shell
$ dsh sre teardown YOUR_SRE_NAME
:::

::::{admonition} Tearing down an SRE is destructive and irreversible
:class: danger
Running `dsh sre teardown` will destroy **all** resources deployed within the SRE.
Ensure that any desired outputs have been extracted before deleting the SRE.
**All** data remaining on the SRE will be deleted.
The user groups for the SRE on Microsoft Entra ID will also be deleted.
::::

- Use {typer}`dsh shm teardown` if you want to teardown the deployed SHM:

:::{code} shell
$ dsh shm teardown
:::

::::{admonition} Tearing down an SHM
:class: warning
Tearing down the SHM permanently deletes **all** remotely stored configuration and state data.
Tearing down the SHM also renders the SREs inaccessible to users and prevents them from being fully managed using the CLI.
All SREs associated with the SHM should be torn down before the SHM is torn down.
::::

## Updating SREs

SREs are modified by updating the configuration then running the deploy command.

- The existing configuration for the SRE can be shown using {typer}`dsh config show`:

:::{code} shell
$ dsh config show YOUR_SRE_NAME
:::

- If you do not have a local copy, you can write one with the `--file` option:

:::{code} shell
$ dsh config show YOUR_SRE_NAME --file YOUR_SRE_NAME.yaml
:::

- Edit the configuration file locally, and upload the new version using {typer}`dsh config upload`:

:::{code} shell
$ dsh config upload YOUR_SRE_NAME.yaml
:::

- You will be shown the differences between the existing configuration and the new configuration and asked to confirm that they are correct.
- Finally, deploy your SRE using {typer}`dsh sre deploy` to apply any changes:

:::{code} shell
$ dsh sre deploy YOUR_SRE_NAME
:::

::::{admonition} Changing administrator IP addresses
:class: warning
The administrator IP addresses declared in the SRE configuration are used to create access rules for SRE infrastructure.
Therefore, after an SRE has been deployed, some changes can only be made from IP addresses on that list.

As a consequence, if you want to update the list of administrator IP addresses, for example to add a new administrator, you must do so from an IP address that is already allowed.
::::

::::{admonition} Changing disk sizes
:class: warning
Updating the size of either the OS disk or the data disk is not possible via DSH [due to Pulumi limitations](https://github.com/pulumi/pulumi-azure-native/issues/3952).
These changes need to happen manually after VM deallocation.
::::

### Storage account names when upgrading

New SRE storage accounts use collision-resistant names when the stack name would otherwise be truncated.
The readable account purpose is followed by a hash of the complete stack name, so SREs with the same shortened prefix receive distinct names.
This applies to desired-state, configuration, sensitive-data and user-data storage.

Existing storage accounts retain the physical account names recorded in their Pulumi state.
The storage resources use Pulumi's `ignore_changes` option for `account_name` so that changing the generated name does not itself request an account replacement.
New accounts still receive the generated name on their first deployment, while references to existing accounts use the names returned by the resource.
See [Pulumi's ignored property documentation](https://www.pulumi.com/docs/iac/concepts/resources/options/ignorechanges/) for details.

::::{admonition} Preserve state and review the deployment plan
:class: warning
Keep a recoverable backup of the existing Pulumi state and storage data before an upgrade.
Check that the deployment plan retains each existing storage account and its name; stop if it proposes a storage replacement, deletion or unexpected account creation.
Do not delete the stack state or recreate an SRE to adopt the new naming convention.
If state has been lost or an account is not managed in that state, recover or explicitly import the existing resources before deploying.
These safeguards do not migrate data between accounts, repair an existing collision, or prevent a deliberate teardown or replacement caused by other configuration changes.
::::
