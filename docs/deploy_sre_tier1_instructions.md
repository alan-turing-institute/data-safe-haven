# Tier1 Secure Research Environment Build Instructions

> :warning: This document provides instructions for deploying a Tier 1
> environment **only**. If you want to deploy any other tiwer, please follow
> [these instructions](./deploy_sre_instructions.md).

> :warning: This documentation is temporary pending the integration of Tier 1
> environments with AD

## Contents
- [:seedling: Prerequisites](#seedling-prerequisites)
- [:clipboard: Define SRE Configuration](#clipboard-define-sre-configuration)
- [:registered: Deploy Key Vault](#registered-deploy-key-vault)
- [:bicyclist: Optional: Declare Users](#bicyclist-optional-declare-users)
- [:computer: Deploy and Configure VM](#computer-deploy,-and-configure-vm)
- [:floppy_disk: Uploading Data](#floppy_disk-uploading-data)

## :seedling: Prerequisites

- :warning: As the deployment process depends on
  [Ansible](https://www.ansible.com) you must be on a [system supported by
  ansible](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
  (Linux, OSX, BSD, Solaris)
- The following packages are required
  - Powershell
  - Azure Powershell Module
  - ansible
  - python > 3.6
  - qrencode
  - oathtool (On OSX this is contained without `oath-toolkit` on homebrew)
- A SHM must be deployed. However, **it is not necessary to make user accounts**
  in the SHM AD as they will not be used.

## :clipboard: Define SRE Configuration

- Follow the steps
  [here](./deploy_sre_instructions.md#clipboard-define-sre-configuration) to
  declare the SHM and SRE configuration properties and generate the full SRE
  configuration.

## :registered: Deploy Key Vault

On your **deployment machine**.
- Create a key vault in the SRE subscription by running
  `./Setup_SRE_KeyVault_And_Users.ps1 -configId <SRE config ID>`, where the
  `<SRE config ID>` is `<SHM ID><SRE ID>` for the full config file you are
  using. For example, the full config file `sre_testcsandbox_full_config` will
  have `<SRE config ID>` equal to `testcsandbox`.

## :bicyclist: Optional: Declare Users

On your **deployment machine**.
- This step is optional at deploy time. If no users are declared, none will be
  created and they may be added at a later time.
- The users file is a [YAML](https://yaml.org) file. There is one top-level key
  `users` which contains a list of users.
- Each users has
  - Real name
  - Username
  - **Absolute path** to their public SSH key
  - Admin flag (if true can use sudo)
  - Enabled flag (if true can login)
- Here is an example users file
```yaml
---
users:
  - name: Harry Lime
    username: harry
    keyfile: ~/keys/id_harry_rsa.pub
    admin: false
    enabled: true
  - name: Keyser Soze
    username: keyser
    keyfile: ~/.ssh/id_keyser_rsa.pub
    admin: true
    enabled: false
```

## :computer: Deploy, and Configure VM

On your **deployment machine**.
- Deploy a Tier 1 VM by running `./Setup_SRE_Tier1.ps1 -configId <SRE config
  ID>` where the config ID is `<SHM ID><SRE ID>` for the config file you are
  using.
  - If you have a users file pass its path with the `-usersYAMLPath` argument. If
    not a vm with no additional user accounts will be created and you may add
    users later.
- If you have not connected to the VM before, this script will ask you if you
  want to connect as the authenticity of the host cannot be established. At this
  point enter `yes`.
- If you are creating new TOTP hashes for new users there are **expected
  failures** in the Ansible play. In particular, looking up the existing TOTP
  hashes for these users will fail. This is expected and not a problem as it
  prompts the next task to create a TOTP hash for those users.
- The CoCalc container is large and pulling it may take some time (~20 minutes).
- To add, or disable user accounts, edit the users file and re-run
  `./Setup_SRE_Tier1.ps1`.

## :floppy_disk: Uploading Data

- `./Setup_SRE_Tier1.ps1` creates a storage account named `sre<sre
  id>ingress<random string>` where `<sre id>` is the SRE ID in lower case and
  `<random string>` is a random set of lower case characters unique to the SRE.
- Within that storage account is a file share called `ingress`. This share is
  mounted at `/data` on the Tier 1 VM.
- You may upload data to `ingress` using the [Azure Storage
  Explorer](https://azure.microsoft.com/en-us/features/storage-explorer/).
