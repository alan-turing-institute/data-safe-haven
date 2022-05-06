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
  subscription_name: <my subscription name>
  admin_group_id: <the ID of an Azure security group that contains all administrators>
  location: <Azure location where resources should be deployed>
```

Run the following:

- `dsh init --config <my config file> --project <my project directory>`
- `dsh deploy --config <my config file>`

Now enter `<my project directory>/kubernetes` and run

- `kubectl --kubeconfig kubeconfig-<my project name>.yaml get nodes`