# Management

## Managing users

### Add users to the Data Safe Haven

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

### List available users

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

### Assign existing users to an SRE

1. You can do this directly in your Entra tenant by adding them to the **Data Safe Haven SRE _YOUR\_SRE\_NAME_ Users** group, following the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/groups-view-azure-portal#add-a-group-member).

2. Alternatively, you can add multiple users from the command line:

    ```{code} shell
    $ dsh users register YOUR_SRE_NAME -u USERNAME_1 -u USERNAME_2
    ```

    where you must specify the usernames for each user you want to add to this SRE.

    :::{important}
    Do not include the Entra ID domain part of the username, just the part before the @.
    :::

### Manually register users for self-service password reset

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

## Managing SREs

### List available SRE configurations and deployment status

- Run the following if you want to check what SRE configurations are available in the current context, and whether those SREs are deployed

```{code} shell
$ dsh config available
```

which will give output like the following

```{code} shell
Available SRE configurations for context 'green':
┏━━━━━━━━━━━━━━┳━━━━━━━━━━┓
┃ SRE Name     ┃ Deployed ┃
┡━━━━━━━━━━━━━━╇━━━━━━━━━━┩
│ emerald      │ x        │
│ jade         │          │
│ olive        │          │
└──────────────┴──────────┘
```

### Remove a deployed Data Safe Haven

- Run the following if you want to teardown a deployed SRE:

```{code} shell
$ dsh sre teardown YOUR_SRE_NAME
```

::::{admonition} Tearing down an SRE is destructive and irreversible
:class: danger
Running `dsh sre teardown` will destroy **all** resources deployed within the SRE.
Ensure that any desired outputs have been extracted before deleting the SRE.
**All** data remaining on the SRE will be deleted.
The user groups for the SRE on Microsoft Entra ID will also be deleted.
::::

- Run the following if you want to teardown the deployed SHM:

```{code} shell
$ dsh shm teardown
```

::::{admonition} Tearing down an SHM
:class: warning
Tearing down the SHM permanently deletes **all** remotely stored configuration and state data.
Tearing down the SHM also renders the SREs inaccessible to users and prevents them from being fully managed using the CLI.
All SREs associated with the SHM should be torn down before the SHM is torn down.
::::

## Managing data ingress and egress

### Data Ingress

It is the {ref}`role_data_provider_representative`'s responsibility to upload the data required by the safe haven.

The following steps show how to generate a temporary, write-only upload token that can be securely sent to the {ref}`role_data_provider_representative`, enabling them to upload the data:

- In the Azure portal select **Subscriptions** then navigate to the subscription containing the relevant SHM
- Search for the resource group: `shm-<YOUR_SHM_NAME>-sre-<YOUR_SRE_NAME>-rg`, then click through to the storage account ending with `sensitivedata`
- Browse to **{menuselection}`Settings --> Networking`** and ensure that the data provider's IP address is one of those allowed under the **Firewall** header
    - If it is not listed, modify and reupload the SRE configuration and redeploy the SRE using the `dsh` CLI, as per {ref}`deploy_sre`
- Browse to **{menuselection}`Data storage --> Containers`** from the menu on the left hand side
- Click **ingress**
- Browse to **{menuselection}`Settings --> Shared access tokens`** and do the following:
    - Under **Signing method**, select **User delegation key**
    - Under **Permissions**, check these boxes:
        - **Write**
        - **List**
    - Set a 24 hour time window in the **Start and expiry date/time** (or an appropriate length of time)
    - Leave everything else as default and click **{guilabel}`Generate SAS token and URL`**
    - Copy the **Blob SAS URL**

      ```{image} ingress_token_write_only.png
      :alt: write-only SAS token
      :align: center
      ```

- Send the **Blob SAS URL** to the data provider through a secure channel
- The data provider should now be able to upload data
- Validate successful data ingress
    - Browse to **{menuselection}`Data storage --> Containers`** (in the middle of the page)
    - Select the **ingress** container and ensure that the uploaded files are present

### Data egress

```{important}
Assessment of output must be completed **before** an egress link is created.
Outputs are potentially sensitive, and so an appropriate process must be applied to ensure that they are suitable for egress.
```

The {ref}`role_system_manager` creates a time-limited and IP restricted link to remove data from the environment.

- In the Azure portal select **Subscriptions** then navigate to the subscription containing the relevant SHM
- Search for the resource group: `shm-<YOUR_SHM_NAME>-sre-<YOUR_SRE_NAME>-rg`, then click through to the storage account ending with `sensitivedata`
- Browse to **{menuselection}`Settings --> Networking`** and check the list of pre-approved IP addresses allowed under the **Firewall** header
    - Ensure that the IP address of the person to receive the outputs is listed
    - If it is not listed, modify and reupload the SRE configuration and redeploy the SRE using the `dsh` CLI, as per {ref}`deploy_sre`
- Browse to **{menuselection}`Data storage --> Containers`**
- Select the **egress** container
- Browse to **{menuselection}`Settings --> Shared access tokens`** and do the following:
    - Under **Signing method**, select **User delegation key**
    - Under **Permissions**, check these boxes:
        - **Read**
        - **List**
    - Set a time window in the **Start and expiry date/time** that gives enough time for the person who will perform the secure egress download to do so
    - Leave everything else as default and press **{guilabel}`Generate SAS token and URL`**
    - Copy the **Blob SAS URL**

      ```{image} egress_token_read_only.png
      :alt: Read-only SAS token
      :align: center
      ```

- Send the **Blob SAS URL** to the relevant person through a secure channel
- The appropriate person should now be able to download data

### The output volume

Once you have set up the egress connection in Azure Storage Explorer, you should be able to view data from the **output volume**, a read-write area intended for the extraction of results, such as figures for publication.
On the workspaces, this volume is `/mnt/output` and is shared between all workspaces in an SRE.
For more information on shared SRE storage volumes, consult the {ref}`Safe Haven User Guide <role_researcher_shared_storage>`.
