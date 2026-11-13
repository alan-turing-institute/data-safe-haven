(upgrade_shm)=

# Upgrade an existing management environment in place

An existing Safe Haven Management environment (SHM) can be updated without
tearing it down. The SHM holds shared resources, including the Azure storage
account used for the Pulumi backend, DNS configuration, and the application
credentials used to deploy Secure Research Environments (SREs).

These instructions describe re-running the **SHM deployment** using an updated
Data Safe Haven CLI. Upgrading the CLI package alone does **not** upgrade any
deployed Azure resources.

:::{important}
Do **not** run `dsh shm teardown` to upgrade. That command removes the SHM
resource group and is not an in-place update. Back up your configuration and
review [release notes](https://github.com/alan-turing-institute/data-safe-haven/releases)
for version-specific migration instructions before making changes.

Schedule a maintenance window when managing production SREs: re-running
`dsh shm deploy` **always creates a new Pulumi Entra application secret** and
writes it to the SHM Key Vault. Other SRE management operations may need to
refresh their credentials after this rotation.
:::

## 1. Record the current context and configuration

Use the same administrative machine and credentials you normally use for
deployments. Confirm which SHM is selected before changing anything:

:::{code} shell
$ dsh --version
$ dsh context show
$ dsh config show-shm --file shm-before-upgrade.yaml
:::

Review the saved configuration and store it securely. Keep the existing
`DSH_CONFIG_DIRECTORY` setting (if used), the same context, and access to its
Azure subscription and Entra tenant.

Also verify that the permissions required for {ref}`deploy_shm` remain in
place. Do not update an SHM while another administrator is deploying or tearing
down its SREs.

## 2. Update the CLI

Check the [supported versions](https://github.com/alan-turing-institute/data-safe-haven/blob/develop/SECURITY.md)
and review the [release history](https://github.com/alan-turing-institute/data-safe-haven/releases)
before installing the desired release.

If you installed DSH with `pipx` as described in the [deployment guide](index.md), update it
using:

:::{code} shell
$ pipx upgrade data-safe-haven
$ dsh --version
:::

If the installed version was intentionally pinned, install the approved version
explicitly instead of automatically upgrading to the latest available release.
Installing a new local CLI version does not itself mutate the running SHM.

## 3. Reapply the existing SHM configuration

Confirm the selected context again, then run the SHM deployment command
**without the first-deployment configuration flags**:

:::{code} shell
$ dsh context show
$ dsh shm deploy
:::

For an existing SHM, the command loads the configuration from the remote
storage account and ensures that its managed resources exist. Supplying
`--fqdn`, `--entra-tenant-id`, or `--location` may change the configuration:
if a difference is presented, inspect it rather than automatically approving
it. Keep the original domain, tenant, and region for a routine in-place update.

You may be prompted to authenticate with both Azure CLI and Microsoft Graph.
The deployment may rotate the Entra application secret even when other
configuration values are unchanged.

## 4. Verify the update

After the deployment reports success, check the selected context and remotely
stored configuration:

:::{code} shell
$ dsh --version
$ dsh context show
$ dsh config show-shm --file shm-after-upgrade.yaml
:::

Compare `shm-after-upgrade.yaml` to your saved configuration, paying
particular attention to the domain name, Entra tenant ID, and Azure location.
Check that the SHM resources and any existing SRE management workflows still
work before declaring the maintenance complete.

If a deployment fails, retain its error logs and the original configuration.
Do not tear down the SHM as a recovery step. Restoring an earlier CLI version
does not automatically roll back changes to Azure resources or the rotated
Entra application secret; investigate those changes before retrying.
