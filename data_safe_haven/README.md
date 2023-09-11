# Requirements

Install the following requirements before starting

- [Poetry](https://python-poetry.org/docs/#installation)
- [Pulumi](https://www.pulumi.com/docs/get-started/install/)

## Deploying a Data Safe Haven

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

You will be prompted for various settings.
Run `dsh deploy shm -h` to see the necessary command line flags and provide them as arguments.

- Add one or more users from a CSV file with columns named (`GivenName`, `Surname`, `Phone`, `Email`, `CountryCode`).
  Note that the phone number must be in full international format.
  Note that the country code is the two letter `ISO 3166-1 Alpha-2` code.

```bash
> dsh admin add-users <my CSV users file>
```

- Next deploy the infrastructure for one or more Secure Research Environments (SREs) [approx 30 minutes]:

```bash
> dsh deploy sre <SRE name>
```

You will be prompted for various settings.
Run `dsh deploy sre -h` to see the necessary command line flags and provide them as arguments.

- Next add one or more existing users to your SRE

```bash
> dsh admin register-users -s <SRE name> <username1> <username2>
```

where you must specify the usernames for each user you want to add to this SRE

## Administering a Data Safe Haven

- Run the following to list the currently available users

```bash
> dsh admin list-users
```

## Removing a deployed Data Safe Haven

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
