# Requirements
Install the following requirements before starting

- [kubectl](https://kubernetes.io/docs/tasks/tools/)
- [Poetry](https://python-poetry.org/docs/#installation)
- [Pulumi](https://www.pulumi.com/docs/get-started/install/)

# Deploying a Data Safe Haven
Create a config file with the following structure:

```yaml
environment:
  name: <my project name>
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