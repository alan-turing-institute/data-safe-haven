# Managing a Data Safe Haven

## Add users to the Data Safe Haven

:::{important}
You will need a full name, phone number, email address and country for each user.
:::

1. You can add users directly in your Entra tenant, following the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-create-delete-users).

2. Alternatively, you can add multiple users from a CSV file with columns named (`GivenName`, `Surname`, `Phone`, `Email`, `CountryCode`).

```{code} shell
$ dsh users add <my CSV users file>
```

:::{warning}

- the phone number must be in full international format.
- the country code is the two letter  ISO 3166-1 Alpha-2  code.

:::

## Assign existing users to an SRE

1. You can do this directly in your Entra tenant by adding them to the `Data Safe Haven SRE <name>` group, following the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/groups-view-azure-portal#add-a-group-member).

2. Alternatively, you can add multiple users from the command line:

```{code} shell
$ dsh users register -s <SRE name> <username1> <username2>
```

where you must specify the usernames for each user you want to add to this SRE.

## Listing available users

1. You can do this in your Entra tenant by browsing to `Identity > Users > All users.`.

2. You can do this at the command line by running the following command:

```{code} shell
$ dsh users list
```

## Removing a deployed Data Safe Haven

- Run the following if you want to teardown a deployed SRE:

```{code} shell
$ dsh sre teardown <SRE name>
```

- Run the following if you want to teardown the deployed SHM:

```{code} shell
$ dsh shm teardown
```

- Run the following if you want to teardown the deployed Data Safe Haven context:

```{code} shell
$ dsh context teardown
```
