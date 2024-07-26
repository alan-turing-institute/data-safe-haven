(configure_entra_id)=

# Configure Microsoft Entra ID

These instructions will configure the [Microsoft Entra ID](https://www.microsoft.com/en-gb/security/business/identity-access/microsoft-entra-id) where you will manage your users.
You only need one Microsoft Entra ID for your deployment of the Data Safe Haven.

## Create a native Microsoft Entra administrator account

If you created a new Microsoft Entra tenant, an external administrator account will have been automatically created for you.
If you do not already have access to a **native** administrator account, create one using the steps below.

:::{admonition} How to create a native Entra administrator
:class: dropdown hint
Follow the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-create-delete-users#create-a-new-user).
Use the following settings:

- `Basics` tab:
    - **User principal name:** `entra.admin.<firstname>.<lastname>`
        - If you have a choice of domains use `<your organisation>.onmicrosoft.com`, which will create a clearer separation between administrators and users
    - **Display name:** `Entra Admin - Firstname Lastname`
    - **Other fields:** leave them with their default values
- `Properties` tab:
    - **Usage location:** set to the country being used for this deployment
- `Assigments` tab:
    - Click `+ Add role`
    - Search for `Global Administrator`, check the box and click the `Select` button

:::

## Register allowed authentication methods

In this section, you will determine which methods are permitted for multi-factor authentication (MFA).
This is necessary both to secure logins and to allow users to set their own passwords.

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **Protection > Authentication methods** from the menu on the left side
- Click **Manage > Policies** on the internal menu on the left side
- For each of `Microsoft Authenticator`, `Third-party software OATH tokens`, `SMS` and `Email OTP` click on the method name
    - Ensure the slider is set to `Enabled` and the target to `All users`
    - Click the `Save` button

## Activate a native Microsoft Entra account

In order to use this account you will need to activate it.
Start by setting up authentication methods for this user, following the steps below.

:::{admonition} How to set up authentication for an Entra user
:class: dropdown hint

- Follow the instructions [here](https://learn.microsoft.com/en-us/entra/identity/authentication/howto-mfa-userdevicesettings#add-authentication-methods-for-a-user).
- Ensure that you provide **both** a phone number **and** an email address.

:::

Now you can reset the password for this user, following the steps below.

:::{admonition} How to reset your Entra user password
:class: dropdown hint

- Follow the instructions [here](https://passwordreset.microsoftonline.com/) to set your password
- You will need access to the phone number and/or email address from the previous step

:::

## Delete any external administrators

:::{warning}
In this step we will delete any external admin account which might belong to Microsoft Entra ID.
Before you do this, you **must** ensure that you can log into Entra using your **native** administrator account.
:::

Start by identifying whether you have any external users.

:::{admonition} How to identify external users
:class: dropdown hint

The **User principal name** field for external users will contain the external domain and will have `#EXT#` before the `@` sign.
:::

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Click on your profile picture at the top right of the page
- Log out of any accounts using the `Sign out` button
- Log in with your **native** administrator credentials
- For each **external** user follow the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-create-delete-users#delete-a-user) to delete the account

## Create additional administrators

:::{important}
In order to avoid being a single point of failure, we strongly recommend that you add other administrators in addition to yourself.
:::

For each other person who will act as an administrator, create an account for them following the steps above and then allow them to reset their own password.

:::{caution}
You may want to set up an emergency administrator to ensure access to this tenant is not lost if you misconfigure MFA.
To do so, follow the instructions [here](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/security-emergency-access).
Since this account will be exempt from normal login policies, it should not be used except when **absolutely necessary**.
:::

## Purchase Microsoft Entra licences

At least one user needs to have a [Microsoft Entra Licence](https://www.microsoft.com/en-gb/security/business/microsoft-entra-pricing) assigned in order to enable [self-service password reset](https://learn.microsoft.com/en-us/entra/identity/authentication/concept-sspr-licensing) and conditional access policies.

:::{tip}
P1 Licences are sufficient but you may use another licence if you prefer.
:::

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **Identity > Billing > Licenses** from the menu on the left side
- Click on `All products` on the internal menu on the left side
- If you have not currently licenced a product:
    - Click on `+Try/Buy` and choose a suitable product
    - Click the `Activate` button
    - Wait for the selected licence to appear on the `All products` list (this may take several minutes)

## Enable self-service password reset

In order to enable self-service password reset (SSPR) you will need to do the following:

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **Protection > Password reset** from the menu on the left side
- Click **Manage > Properties** on the internal menu on the left side
- Under the option `Self service password reset enabled`, choose **All**

## Disable security defaults

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **Identity > Overview > Properties** from the menu on the left side
- Select **Manage security defaults**
- In the pop-up menu on the right, set
    - **Security defaults** to `Disabled (not recommended)`
    - Select **My organization is planning to use Conditional Access**
    - Click the `Save` button
- At the prompt click the `Disable` button

## Apply conditional access policies

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **Protection > Conditional Access** from the menu on the left side
- Click **Policies** on the internal menu on the left side

### Require MFA

- Create a new policy named `Require MFA`
- Under `Users` set:
    - **Include**: Select `All users`
    - **Exclude**:
        - Check `Users and groups`
        - Select your **Emergency Access admin** account here if you have one
- Under `Target resources` set:
    - **Include**: Select `All cloud apps`
- Under `Conditions` select `Device platforms` and set:
    - **Configure:** `Yes`
    - **Select device platforms:** Check all the boxes
    - Click `Done`
- Under `Grant`:
    - Check `Grant access`
    - Check `Require multi-factor authentication`
    - Click `Select`
- Under `Session`:
    - Check `Sign-in frequency`
    - Check `Periodic reauthentication`
        - Set the value to `1 day(s)`
- Under `Enable policy` select `On`
    - Check `I understand that my account will be impacted by this policy. Proceed anyway.`
- Click the `Create` button

### Restrict Microsoft Entra ID access

- Create a new policy named `Restrict Microsoft Entra ID access`
- Under `Users` set:
    - **Include**: Select `All users`
    - **Exclude**:
        - Check `Directory roles`
        - In the drop-down menu select `Global administrator`
- Under `Target resources` set:
    - **Include**:
        - Select `Select apps`
        - Click `Select`
        - In the pop-up menu on the right, select
            - `Windows Azure Service Management API` and
            - `Microsoft Graph Command Line Tools` then
        - Click `Select`
    - **Exclude**: Leave unchanged as `None`
- Under `Grant`:
    - Check `Block access`
    - Click `Select`
- Under `Enable policy` select `On`
- Click the `Create` button
