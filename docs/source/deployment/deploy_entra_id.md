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
    - set the `Country or Region` to whatever region is appropriate for your deployment (e.g. `United Kingdom`)


### Get the Microsoft Entra Tenant ID

- Go to the [Entra homepage](https://entra.microsoft.com/)
- Click on your username / profile icon in the top right and select `Switch directory`
  - Ensure that you have selected the directory you chose above
- From the left hand menu, click `Overview` and note the `Tenant ID`
  ```{image} ../_static/deployment/entra_tenant_id.png
  :alt: Finding the Microsoft Entra tenant ID
  :align: center
  ```