(desired_state_development)=

# Develop and troubleshoot workspace desired state

This guide is for developers and operators who need to inspect, test or update
the Ansible configuration applied to Data Safe Haven (DSH) workspace VMs.
For first-time provisioning, see {ref}\`deploy_sre\`.

## How desired state reaches a workspace

The source of the workspace playbook is
\`data_safe_haven/resources/workspace/ansible/desired_state.yaml\`.
Its supporting files live beside it in \`tasks/\`, \`templates/\`,
\`files/\` and \`host_vars/\`.

The \`SREDesiredStateComponent\` Pulumi component in
\`data_safe_haven/infrastructure/programs/sre/desired_state.py\` uploads those
files to an Azure Blob container named \`desiredstate\`, preserving paths
relative to the \`ansible/\` directory. Pulumi also generates
\`vars/pulumi_vars.yaml\` in that container from deployment configuration.
**The generated variables can contain secrets.** Do not copy them into Git,
send them in a bug report or print their contents in logs.

On each workspace, cloud-init mounts this container **read-only** over NFSv3 at
\`/var/local/ansible\`, as defined in
\`data_safe_haven/resources/workspace/workspace.cloud_init.mustache.yaml\`.
Editing that mount locally on a workspace is therefore not the supported way
to update desired state.

The same cloud-init template installs:

- \`desired-state.service\`: a one-shot systemd service that runs
  \`/root/desired_state.sh\`, which changes directory to
  \`/var/local/ansible\` and executes \`ansible-playbook desired_state.yaml\`.
  The service includes a one-minute delay before starting.
- \`desired-state.timer\`: a persistent, daily systemd timer.
- An initial run after the desired-state mount and Pulumi variables become
  available.

Because the playbook runs on **each workspace VM**, uploading a file to the
shared container does not itself run Ansible on any existing workspace.

## Develop and test a change

Start from the source code for the DSH version deployed in the SRE, then:

1. Modify the corresponding task, template or playbook in
   \`data_safe_haven/resources/workspace/ansible/\`.
1. Review the change, including its security impact, dependencies and
   idempotence. In particular, verify how a task behaves both when a feature
   is enabled and when it is later disabled.
1. Run the available static checks and tests locally. Use the repository's
   [contribution guidelines](https://github.com/alan-turing-institute/data-safe-haven/blob/develop/CONTRIBUTING.md)
   for the standard developer environment.
1. Test in an appropriately isolated non-production SRE before deploying to a
   production environment.
1. Prefer the normal \`dsh sre deploy\` workflow for managed source changes.
   An ad-hoc upload, described below, is useful for controlled development
   but may be replaced by a later Pulumi deployment.

For example, after changing an existing Ansible task:

:::{code} shell
ansible-lint data_safe_haven/resources/workspace/ansible/desired_state.yaml
git diff --check
:::

Ansible also supports
[playbook syntax checks](https://docs.ansible.com/ansible/latest/cli/ansible-playbook.html)
and [check mode](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_checkmode.html).
Check mode is useful but **not a substitute for integration testing**: some
modules or command tasks cannot accurately predict their changes.

## Upload a reviewed file without a full deployment

A suitably authorised developer can update an individual asset in the
\`desiredstate\` container using either the Azure portal or the Azure CLI.
This is a change to the **shared configuration for an SRE**, not a per-VM
operation. Coordinate the change with the SRE administrator first.

:::{warning}
Only use this workflow for an authorised deployment. Select the **correct
subscription, SRE and desired-state storage account** before uploading.
The storage account uses private networking, so your machine must have
appropriate network access as well as Azure permissions.

Never upload or overwrite \`vars/pulumi_vars.yaml\` manually: Pulumi generates
it from deployment settings, including sensitive values. Do not enable public
storage access to work around a private-endpoint connectivity problem.
:::

### Azure CLI: one file

First, sign in and select the correct subscription. Identify the SRE's
desired-state storage account from its resources in the Azure portal or from
your authorised deployment outputs. Set \`ACCOUNT\` to **that actual account
name**; the example below is not an account-discovery command.

:::{code} shell
az login
az account set --subscription "SUBSCRIPTION_NAME_OR_ID"
ACCOUNT="ACTUAL_DESIRED_STATE_STORAGE_ACCOUNT"
:::

From the repository root, the following example backs up and uploads just
\`tasks/package_proxy.yaml\`. Substitute the relative path you actually
changed. The backup is local to the machine executing these commands.

:::{code} shell
mkdir -p ./desired-state-backups
chmod 700 ./desired-state-backups

az storage blob download \
  --account-name "$ACCOUNT" \
  --container-name desiredstate \
  --name tasks/package_proxy.yaml \
  --file ./desired-state-backups/package_proxy.yaml \
  --auth-mode login

az storage blob upload \
  --account-name "$ACCOUNT" \
  --container-name desiredstate \
  --name tasks/package_proxy.yaml \
  --file data_safe_haven/resources/workspace/ansible/tasks/package_proxy.yaml \
  --overwrite true \
  --auth-mode login
:::

The Blob name must use the path **relative to \`ansible/\`**. Keep downloaded
backups, especially configuration files, in a restricted location outside the
repository; do not commit them. The CLI requires an Azure role that permits
Blob data operations and access to the private storage endpoint.

For an intentionally reviewed update to **the full directory**, the Azure CLI
also supports
[\`az storage blob upload-batch\`](https://learn.microsoft.com/en-us/cli/azure/storage/blob#az-storage-blob-upload-batch).
Use \`-s data_safe_haven/resources/workspace/ansible -d desiredstate\` with
the correct \`--account-name\`, \`--auth-mode login\` and \`--overwrite true\`.
Unlike the single-file command, a batch can replace many live playbooks and
templates, so review its complete scope and backup the existing assets first.

### Azure portal

In the correct subscription, navigate to **Storage accounts**, select the
SRE's desired-state storage account, then open **Data storage → Containers →
desiredstate**. Locate the Blob corresponding to the relative source path and
use **Upload** with replacement of the existing Blob, where available.
Review the target Blob path and replacement setting before confirming.
The same private-network and access-control restrictions apply.

## Run the updated desired state on a workspace

Connect to a **non-production workspace VM** through the approved
administrative route. Wait for cloud-init and the NFS mount to be ready, and
verify that the updated asset is visible under \`/var/local/ansible\`.
Then use the installed systemd service:

:::{code} shell
sudo systemctl start desired-state.service
sudo systemctl status desired-state.service --no-pager
sudo journalctl -u desired-state.service -n 100 --no-pager
systemctl list-timers desired-state.timer
:::

For a more targeted *preview*, run Ansible from the mounted playbook directory
with \`--check --diff\` and an appropriate task tag, for example:

:::{code} shell
cd /var/local/ansible
sudo ansible-playbook desired_state.yaml --syntax-check
sudo ansible-playbook desired_state.yaml --check --diff --tags package_proxies
:::

Review that the tag exists in \`desired_state.yaml\`. Check mode may not fully
exercise a task. To apply a reviewed change using the normal systemd entry
point, start \`desired-state.service\` as shown above. Do not mistake the
daily timer for an immediate reload; it runs on its configured schedule.

## Troubleshooting and rollback

If the mount is missing, the variables are not yet present, or a task fails:

- Check \`findmnt /var/local/ansible\`, the systemd service status, and its
  journal. The cloud-init template waits for the mount and variables during
  initial deployment.
- Confirm the SRE subscription, private storage endpoint, Blob path, and
  the version of the uploaded files. A successful Blob upload does not prove
  Ansible has run successfully on every workspace.
- Restore a reviewed previous version of the affected Blob using the same
  *single-file* upload process, then run and verify the service again.
- Check the application-specific functionality afterwards, including the
  [workspace smoke tests](smoke_tests.md).

For long-term fixes, update the repository source and deploy through the
standard SRE management workflow. An ad-hoc hotfix is not a replacement for
versioned infrastructure as code.

See the upstream [Ansible playbook guide](https://docs.ansible.com/ansible/latest/playbook_guide/index.html)
and the [Azure Blob CLI reference](https://learn.microsoft.com/en-us/cli/azure/storage/blob)
for further details.
