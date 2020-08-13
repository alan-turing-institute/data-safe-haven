# Stand-alone Tier1 Collaborative Environment

This directory contains configuration files to deploy a Stand-alone, tier1,
collaborative environment. This machine will have internet access. Users may
access this machine via SHH or can work collaboratively using the pre-deployed
CoCalc instance.

## Deployment

### Prerequisites

The deployment and configuration scripts require the following packages,

- bash
- sed
- azure cli
- jq
- ansible

### Provision The Machine

- Login to Azure by running `az login` and follow the instructions.
- Select the appropriate subscription with `az account set -s
  <subscription_id_or_name>`.
- Provision the tier1 VM and infrastructure with the deploy script
  `./deploy.sh`.

### Configure The Machine

- The VM is configured using ansible. Change into the `deployment/tier1/ansible`
  directory.
- The inventory file `hosts.yaml` should have been updated by the deploy script
  to contain the IP address of the tier1 VM.
- Copy `users_example.yaml` to `users.yaml`.
- Edit `users.yaml` adding all users who need access. Duplicate the template
  user and update the keys with appropriate values,
  - Replace `<real name>` with the users real name
  - Replace `<username>` with the users desired username
  - Replace `<path to public ssh keyfile>` with the path to the users public ssh keyfile
  - The value of `admin` to true if that user should be added to the sudo group
    (_i.e._ given root access on the VM)
- Run `ansible-playbook playbook.yaml -i hosts.yaml`

## Test CoCalc

- CoCalc is running on port 443 of the tier1 VM. However, only port 22 accepts
  inbound traffic.
- To connect to CoCalc, first open an SSH tunnel to connect port 443 on the VM
  to a port on your local machine via SSH (port 22), `ssh <user>@<VM_IP> -L
  8443:localhost:443`.
- You can now access CoCalc by opening a browser and navigating to
  `https://localhost:8443`.
