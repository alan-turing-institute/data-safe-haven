# Requirements

Install the following requirements before starting

- [Poetry](https://python-poetry.org/docs/#installation)
- [Pulumi](https://www.pulumi.com/docs/get-started/install/)

# Deploying a Data Safe Haven

Create a directory where you want to store local configuration files for this deployment.
This is the `project directory`

- Run the following to initialise the deployment [approx 5 minutes]:

```bash
> dsh init
```

You will be prompted for various project settings.
If you prefer to enter these at the command line, run `dsh init -h` to see the necessary command line flags.

- Next deploy the Safe Haven Management (SHM) infrastructure [approx 30 minutes]:

```bash
> dsh deploy shm
```

You will be prompted for various project settings.
If you prefer to enter these at the command line, run `dsh deploy shm -h` to see the necessary command line flags.

- Add one or more users from a CSV file with columns named (`GivenName`, `Surname`, `Phone`, `Email`). Note that the phone number must be in full international format.

```bash
> dsh users add <my CSV users file>
```

- Next deploy the infrastructure for one or more Secure Research Environments (SREs) [approx 30 minutes]:

```bash
> dsh deploy sre <SRE name> -r <VM1 SKU> -r <VM2 SKU>
```

where you must specify a VM SKU for each user-accessible secure research desktop that you want to deploy
On first run, you will be prompted for various project settings.
If you prefer to enter these at the command line, run `dsh deploy sre -h` to see the necessary command line flags.

- Next add one or more existing users to your SRE

```bash
> dsh users register -s <SRE name> <username1> <username2>
```

where you must specify the usernames for each user you want to add to this SRE

# Administering a Data Safe Haven

- Run the following to list the currently available users

```bash
> dsh users list
```

# Removing a deployed Data Safe Haven

- Run the following if you want to teardown a deployed SRE:

```bash
> dsh teardown sre <SRE name>
```

- Run the following if you want to teardown the deployed SHM:

```bash
> dsh teardown shm
```

- Run the following if you want to teardown the deployed Data Safe Haven backend:

```bash
> dsh teardown backend
```
