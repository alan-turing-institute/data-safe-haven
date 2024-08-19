# Management

## Add users to the Data Safe Haven

:::{important}
You will need a full name, phone number, email address and country for each user.
:::

1. You can add users directly in your Entra tenant, following the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-create-delete-users).

2. Alternatively, you can add multiple users from a CSV file with columns named (`GivenName`, `Surname`, `Phone`, `Email`, `CountryCode`).
    - (Optional) you can provide a `Domain` column if you like but this will otherwise default to the domain of your SHM
    - {{warning}} **Phone** must be in [E.123 international format](https://en.wikipedia.org/wiki/E.123)
    - {{warning}} **CountryCode** is the two letter [ISO 3166-1 Alpha-2](https://en.wikipedia.org/wiki/ISO_3166-1_alpha-2#Officially_assigned_code_elements) code for the country where the user is based

::::{admonition} Example CSV user file
:class: dropdown tip

:::{code} text
GivenName;Surname;Phone;Email;CountryCode
Ada;Lovelace;+44800456456;ada@lovelace.me;GB
Grace;Hopper;+18005550100;grace@nasa.gov;US
:::
::::

```{code} shell
$ dsh users add PATH_TO_MY_CSV_FILE
```

## Listing available users

- You can do this from the [Microsoft Entra admin centre](https://entra.microsoft.com/)

    1. Browse to **{menuselection}`Groups --> All Groups`**
    2. Click on the group named **Data Safe Haven SRE _YOUR\_SRE\_NAME_ Users**
    3. Browse to **{menuselection}`Manage --> Members`** from the secondary menu on the left side

- You can do this at the command line by running the following command:

    ```{code} shell
    $ dsh users list YOUR_SRE_NAME
    ```

    which will give output like the following

    ```
    ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┳━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━┓
    ┃ username                     ┃ Entra ID ┃ SRE YOUR_SRE_NAME ┃
    ┡━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━╇━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━┩
    │ ada.lovelace                 │ x        │ x                 │
    │ grace.hopper                 │ x        │ x                 │
    │ ursula.franklin              │ x        │                   │
    │ joan.clarke                  │ x        │                   │
    └──────────────────────────────┴──────────┴───────────────────┘
    ```

## Assign existing users to an SRE

1. You can do this directly in your Entra tenant by adding them to the **Data Safe Haven SRE _YOUR\_SRE\_NAME_ Users** group, following the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/groups-view-azure-portal#add-a-group-member).

2. Alternatively, you can add multiple users from the command line:

    ```{code} shell
    $ dsh users register YOUR_SRE_NAME -u USERNAME_1 -u USERNAME_2
    ```

    where you must specify the usernames for each user you want to add to this SRE.

    :::{important}
    Do not include the Entra ID domain part of the username, just the part before the @.
    :::

## Manually register users for self-service password reset

:::{tip}
Users created via the `dsh users` command line tool will be automatically registered for SSPR.
:::

If you have manually created a user and want to enable SSPR, do the following

- Go to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **{menuselection}`Users --> All Users`**
- Select the user you want to enable SSPR for
- On the **{menuselection}`Manage --> Authentication Methods`** page fill out their contact info as follows:
    - Ensure that you register **both** a phone number and an email address
        - **Phone:** add the user's phone number with a space between the country code and the rest of the number (_e.g._ +44 7700900000)
        - **Email:** enter the user's email address here
    - Click the **{guilabel}`Save`** icon in the top panel

## Removing a deployed Data Safe Haven

- Run the following if you want to teardown a deployed SRE:

```{code} shell
$ dsh sre teardown YOUR_SRE_NAME
```

- Run the following if you want to teardown the deployed SHM:

```{code} shell
$ dsh shm teardown
```
