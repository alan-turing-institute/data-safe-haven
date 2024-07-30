# Management

## Add users to the Data Safe Haven

:::{important}
You will need a full name, phone number, email address and country for each user.
:::

1. You can add users directly in your Entra tenant, following the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-create-delete-users).

2. Alternatively, you can add multiple users from a CSV file with columns named (`GivenName`, `Surname`, `Phone`, `Email`, `CountryCode`).
    - (Optional) you can provide a `Domain` column if you like but this will otherwise default to the domain of your SHM

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
$ dsh users register <SRE name> -u <username1> -u <username2>
```

where you must specify the usernames for each user you want to add to this SRE.

:::{note}
Usernames are of the format `<GivenName>.<Surname>` and do not include the Entra ID domain.
:::

## Listing available users

1. You can do this in your Entra tenant by browsing to `Entra ID > Groups > Data Safe Haven SRE <name> Users > Members`.

2. You can do this at the command line by running the following command:

```{code} shell
$ dsh users list <SRE name>
```

## Manually register users for self-service password reset

:::{tip}
Users created via the `dsh users` command line tool will be automatically registered for SSPR.
:::

If you have manually created a user and want to enable SSPR, do the following

- Go to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **Users > All Users** from the menu on the left side
- Select the user you want to enable SSPR for
- On the **Manage > Authentication Methods** page fill out their contact info as follows:
    - Phone: add the user's phone number with a space between the country code and the rest of the number (_e.g._ `+44 7700900000`)
    - Email: enter the user's email address here
    - Ensure that you have registered **both** a phone number and an email address
    - Click the `Save` icon in the top panel

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
