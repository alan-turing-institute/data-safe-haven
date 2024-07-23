(deploy_entra_id)=

# Deploy Microsoft Entra ID

These instructions will deploy the [Entra ID](https://www.microsoft.com/en-gb/security/business/identity-access/microsoft-entra-id) where you will manage your users.
This is required to manage your Secure Research Environments (SREs) and **must be** deployed before you create your SHM.

:::{note}
A single SHM can manage all your SREs.
However, you may choose to use multiple SHMs if, for example, you want to separate production and development environments.
:::

## Set up your Entra directory

- If you want to re-use an existing Microsoft Entra directory, you can skip this step

:::{warning}
If you wish to reuse an existing Microsoft Entra directory please make sure you remove any existing DSH-related `Conditional Access Policies` by going to `Security > Conditional Access > Policies` and manually removing the `Restrict Microsoft Entra ID access` and `Require MFA` policies.
:::

- If you want to deploy a dedicated Microsoft Entra directory for use with your DSH deployment, follow [this tutorial](https://learn.microsoft.com/en-us/entra/fundamentals/create-new-tenant)
    - set the `Organisation Name` to something appropriate for your deployment (e.g. `Contoso Production Safe Haven`)
    - set the `Initial Domain Name` to the lower-case version of the `Organisation Name` with spaces and special characters removed (e.g. `contosoproductionsafehaven`)
    - set the `Country or Region` to whichever country is appropriate for your deployment (e.g. `United Kingdom`)


### Get the Microsoft Entra Tenant ID

- Go to the [Entra homepage](https://entra.microsoft.com/)
- Click on your username / profile icon in the top right and select `Switch directory`
  - Ensure that you have selected the directory you chose above
- From the left hand menu, click `Overview` and note the `Tenant ID`
  ```{image} ../_static/deployment/entra_tenant_id.png
  :alt: Finding the Microsoft Entra tenant ID
  :align: center
  ```

### Create Microsoft Entra administrator accounts

A default external administrator account was automatically created for the user you were logged in as when you initially created the Microsoft Entra ID.
This user should also **not be used** for administering the Microsoft Entra ID.

Several later steps will require the use of a **native** administrator account with a valid mobile phone and email address.
You must therefore create and activate a **native** administrator account for each person who will be acting as a system administrator.
After doing so, you can delete the default external user - we strongly recommend that you do so.

:::{tip}
In order to avoid being a single point of failure, we strongly recommend that you add other administrators in addition to yourself.
:::

- Go to the [Entra homepage](https://entra.microsoft.com/)
- Click `Users` in the left hand sidebar then `All Users`
- Click on the `+New user` icon in the top menu and select `Create new user` from the dropdown

For each administrator you want to add, create a new user with the following values:

- `Basics` tab:
  - User principal name: `aad.admin.firstname.lastname` (ensure you select the appropriate domain for your SHM)
  - Display name: `AAD Admin - Firstname Lastname`
  - Other fields: leave them with their default values
- `Properties` tab:
  - Usage location: set to the country being used for this deployment
- `Assigments` tab:
  - Click `+ Add role`
  - Search for `Global Administrator`, check the box and click the `Select` button
- `Review + create` tab:
  - Check that the user properties look something like this:
  ```{image} ../_static/deployment/entra_tenant_id.png
  :alt: Finding the Microsoft Entra tenant ID
  :align: center
  ```
  - Click the `Create` button

### Create Microsoft Entra emergency access administrator account

We also recommend that you create an emergency access administrator account.
This will be exempt from some login policies and should not be used except when **absolute necessary**.

:::{caution}
In particular, you must not use the emergency access account as a shared admin account for routine administration of the Safe Haven.
:::

Create the account as above, using `aad.admin.emergency.access` as the user principal name and `AAD Admin - Emergency Access` as the display name.
Ensure that you copy the auto-generated password and store it securely somewhere.
