# Requirements

Install the following requirements before starting

- [Poetry](https://python-poetry.org/docs/#installation)
- [Pulumi](https://www.pulumi.com/docs/get-started/install/)

# Deploying a Data Safe Haven

Create a config file with the following structure:

```yaml
environment:
  name: <my project name>
  url: <url where the SRE will be hosted>
  vm_sizes: # list of VM sizes of desktops that will be available to end users
    - Standard_D2s_v3
    - Standard_D2s_v3
settings:
  allow_copy: <True/False> (default False) # allow copying of text from the environment
  allow_paste: <True/False> (default False) # allow pasting of text into the environment
azure:
  aad_tenant_id: <the tenant ID of the Azure Active Directory where your users are registered>
  subscription_name: <my subscription name>
  admin_group_id: <the ID of an Azure security group that contains all administrators>
  location: <Azure location where resources should be deployed>
```

- Run the following to initialise the deployment:

```bash
> dsh init --config <my YAML config file>
```

- Next deploy the infrastructure with:

```bash
> dsh deploy --config <my YAML config file>
```

- Add one or more users from a CSV file with columns named (`first_name;last_name;email_address;phone_number`)

```bash
> dsh users --config <my YAML config file> --add <my CSV users file>
```

- Run the following if you want to teardown a deployed environment:

```bash
> dsh teardown --config <my YAML config file>
```
