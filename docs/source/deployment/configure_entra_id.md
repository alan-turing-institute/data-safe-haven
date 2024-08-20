(configure_entra_id)=

# Configure Microsoft Entra ID

These instructions will configure the [Microsoft Entra ID](https://www.microsoft.com/en-gb/security/business/identity-access/microsoft-entra-id) where you will manage your users.
You only need one Microsoft Entra ID for your deployment of the Data Safe Haven.

## Setting up your Microsoft Entra tenant

:::{tip}
We suggest using a dedicated Microsoft Entra tenant for your DSH deployment, but this is not a requirement.

We also recommend using a separate tenant for managing your users from the one where your infrastructure subscriptions live, but this is not a requirement.
:::

If you decide to deploy a new tenant for user management, follow the instructions here:

:::{admonition} How to deploy a new tenant
:class: dropdown note
Follow the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/create-new-tenant).

- set the **Organisation Name** to something appropriate for your deployment (_e.g._ _Contoso Production Safe Haven_)
- set the **Initial Domain Name** to the lower-case version of the organisation name with spaces and special characters removed (_e.g._ _contosoproductionsafehaven_)
- set the **Country or Region** to whichever country is appropriate for your deployment (_e.g._ _United Kingdom_)

:::

## Create a native Microsoft Entra administrator account

If you created a new Microsoft Entra tenant, an external administrator account will have been automatically created for you.
If you do not already have access to a **native** administrator account, create one using the steps below.

:::{admonition} How to create a native Entra administrator
:class: dropdown hint
Follow the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-create-delete-users#create-a-new-user).
Use the following settings:

- **Basics** tab:
    - **User principal name:** entra.admin._FIRST_NAME_._LAST_NAME_
        - If you have a choice of domains use _YOUR_ORGANISATION_.onmicrosoft.com, which will create a clearer separation between administrators and users
    - **Display name:** Entra Admin - _FIRST_NAME_ _LAST_NAME_
    - **Other fields:** leave them with their default values
- **Properties** tab:
    - **Usage location:** set to the country being used for this deployment
- **Assigments** tab:
    - Click the **{guilabel}`+ Add role`** button
    - Search for **Global Administrator**, and check the box
    - Click the **{guilabel}`Select`** button

:::

## Register allowed authentication methods

In this section, you will determine which methods are permitted for multi-factor authentication (MFA).
This is necessary both to secure logins and to allow users to set their own passwords.

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **{menuselection}`Protection --> Authentication methods`** from the menu on the left side
- Browse to **{menuselection}`Manage --> Policies`** from the secondary menu on the left side
- For each of **Microsoft Authenticator**, **SMS**, **Third-party software OATH tokens**, **Voice call** and **Email OTP** click on the method name
    - Ensure the slider is set to **Enable** and the target to **All users**
    - {{bangbang}} For **SMS** ensure that **Use for sign-in** is unchecked
    - {{bangbang}} For **Voice call** switch to the **Configure** tab and ensure that **Office** is checked
    - Click the **{guilabel}`Save`** button

::::{admonition} Microsoft Entra authentication summary
:class: dropdown hint

:::{image} images/entra_authentication_methods.png
:alt: Microsoft Entra authentication methods
:align: center
:::

::::

- Browse to **{menuselection}`Protection --> Authentication methods --> Authentication strengths`** from the menu on the left side
- Click the **{guilabel}`+ New authentication strength`** button
- Enter the following values on the **Configure** tab

:::{admonition} Configure app-based authentication
:class: dropdown hint

- **Name**: App-based authentication
- **Description**: App-based authentication
- Under **{menuselection}`Multi-factor authentication`**:
    - Check **Password + Microsoft Authenticator (Push notification)**
    - Check **Password + Software OATH token**
- Click the **{guilabel}`Next`** button
- Click the **{guilabel}`Create`** button

:::

## Activate your native Microsoft Entra account

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
In this step we will delete any external account with administrator privileges which might belong to Microsoft Entra ID.
Before you do this, you **must** ensure that you can log into Entra using your **native** administrator account.
:::

Start by identifying whether you have any external users.

:::{admonition} How to identify external users
:class: dropdown hint

The **User principal name** field for external users will contain the external domain and will have `#EXT#` before the `@` sign.
:::

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Click on your profile picture at the top right of the page
- Click the **{guilabel}`Sign out`** button to log out of any accounts
- Log in with your native administrator credentials
- Follow the instructions [here](https://learn.microsoft.com/en-us/entra/fundamentals/how-to-create-delete-users#delete-a-user) to delete each external user

:::{note}
We recommend deleting **all** external users, but if these users are necessary, you can instead remove administrator privileges from them.
:::

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
**P1 Licences** are sufficient but you may use another licence if you prefer.
:::

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **{menuselection}`Identity --> Billing --> Licenses`** from the menu on the left side
- Browse to **{menuselection}`All products`** from the secondary menu on the left side
- If you have not currently licenced a product:
    - Click on **{guilabel}`+Try/Buy`** and choose a suitable product
    - Click the **{guilabel}`Activate`** button
- Wait a few minutes until the selected licence appears on the **All products** view

## Enable self-service password reset

In order to enable self-service password reset (SSPR) you will need to do the following:

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **{menuselection}`Protection --> Password reset`** from the menu on the left side
- Browse to **{menuselection}`Manage --> Properties`** from the secondary menu on the left side
- Under the option **Self service password reset enabled**, choose **All**

## Disable security defaults

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **{menuselection}`Identity --> Overview --> Properties`** from the menu on the left side
- Click **{menuselection}`Manage security defaults`** at the bottom of the page
- In the pop-up menu on the right, set
    - **Security defaults** to **Disabled (not recommended)**
    - Select **My organization is planning to use Conditional Access**
    - Click the **{guilabel}`Save`** button
- At the prompt click the **{guilabel}`Disable`** button

## Apply conditional access policies

- Sign in to the [Microsoft Entra admin centre](https://entra.microsoft.com/)
- Browse to **{menuselection}`Protection --> Conditional Access`** from the menu on the left side
- Browse to **{menuselection}`Policies`** from the secondary menu on the left side

### Require MFA

These instructions will create a policy which requires all users (except the emergency administrator if you have created one) to use multi-factor authentication (MFA) to log in.

:::{admonition} Require MFA policy details
:class: dropdown hint

- Create a new policy named **Require MFA**
- Under **{menuselection}`Users`**:
    - **Include**: Select **All users**
    - **Exclude**:
        - Check **Users and groups**
        - If you created an emergency access admin account, select it here
- Under **{menuselection}`Target resources`**:
    - **Include**: Select **All cloud apps**
- Under **{menuselection}`Conditions`**:
    - Select **Device platforms** and set:
        - **Configure:** Select **Yes**
        - **Select device platforms:** Check all the boxes
        - Click the **{guilabel}`Done`** button
- Under **{menuselection}`Grant`**:
    - Check **Grant access**
    - Check **Require authentication strength**
    - In the drop-down menu select **App-based authentication**
    - Click the **{guilabel}`Select`** button
- Under **{menuselection}`Session`**:
    - Check **Sign-in frequency**
    - Check **Periodic reauthentication**
        - Set the value to **1 day(s)**
- Under **{menuselection}`Enable policy`**:
    - Select **On**
    - Check **I understand that my account will be impacted by this policy. Proceed anyway.**
- Click the **{guilabel}`Create`** button

:::

### Restrict Microsoft Entra ID access

These instructions will prevent non-administrators from being able to view the Entra ID configuration.

:::{admonition} Restrict Microsoft Entra ID access policy details
:class: dropdown hint

- Create a new policy named **Restrict Microsoft Entra ID access**
- Under **{menuselection}`Users`**:
    - **Include**: Select **All users**
    - **Exclude**:
        - Check **Directory roles**
        - In the drop-down menu select **Global administrator**
- Under **{menuselection}`Target resources`**:
    - **Include**:
        - Select **Select apps**
        - Click the **{guilabel}`Select`** button
        - In the pop-up menu on the right, select
            - **Windows Azure Service Management API** and
            - **Microsoft Graph Command Line Tools** then
        - Click the **{guilabel}`Select`** button
    - **Exclude**: Leave unchanged as **None**
- Under **{menuselection}`Grant`**:
    - Check **Block access**
    - Click the **{guilabel}`Select`** button
- Under **{menuselection}`Enable policy`**
    - Select **On**
- Click the **{guilabel}`Create`** button

:::
