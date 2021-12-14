(role_researcher_user_guide_guacamole)=

# User Guide: Apache Guacamole

```{include} snippets/01_introduction.partial.md
:relative-images:
```

(roles_researcher_user_guide_setup_mfa)=

```{include} snippets/02_account_setup.partial.md
:relative-images:
```

## {{unlock}} Access the Secure Research Environment

```{include} snippets/03_01_prerequisites.partial.md
:relative-images:
```

### {{house}} Log into the research environment

- Open a **private/incognito** browser session, so that you don't pick up any existing Microsoft logins

- Go to the {ref}`SRE URL <user_guide_sre_url>` given by your {ref}`System Manager <role_system_manager>`.

  ```{note}
  Our example user, Ada Lovelace, participating in the `sandbox` project at a Turing Data Study Group, would navigate to `https://sandbox.projects.turingsafehaven.ac.uk`.
  ```

  ```{important}
  Don't forget the **https://** as you will not be able to login without it!
  ```

- You should arrive at a login page that needs you to enter:

  - your `username@<username domain>`
  - your password

  then click `Login`.

- You should arrive at a login page that looks like the image below:

  ````{note}
  Our example user, Ada Lovelace, participating in the `sandbox` project at a Turing Data Study Group, would enter `ada.lovelace@projects.turingsafehaven.ac.uk` in the `User name` box, enter her password and then click `Login`.
  ```{image} user_guide/logon_environment_guacamole.png
  :alt: Research environment log in
  :align: center
  ```
  ````

- You will now **receive a call or mobile app notification** to authenticate using multifactor authentication (MFA).

  ```{image} user_guide/guacamole_mfa.png
  :alt: MFA trigger
  :align: center
  ```

  {{telephone_receiver}} For the call, you may have to move to an area with good reception and/or press the hash (`#`) key multiple times in-call.

  {{iphone}} For the app you will see a notification saying _"You have received a sign in verification request"_. Go to the app to approve the request.

  ```{caution}
  If you don't respond to the MFA request quickly enough, or if it fails, you may get an error. If this happens, please retry
  ```

- If you are successful, you'll see the a screen with icons for the available apps.

  ```{image} user_guide/guacamole_dashboard.png
  :alt: Research environment dashboard
  :align: center
  ```

  Welcome to the Data Safe Haven! {{wave}}

### {{penguin}} Log into the Secure Research Desktop

The primary method of performing data analysis in the SRE is using the Secure Research Desktop (SRD).

This is a virtual machine (VM) with many different applications and programming languages pre-installed on it.
Once connected to it, you can analyse the sensitive data belonging to your project while remaining completely isolated from the internet.

- Click on one of the `Desktop` connections (for example `Ubuntu0_CPU2_8GB (Desktop)` to connect to the desktop.

```{include} snippets/03_02_srd_login.partial.md
:relative-images:
```

```{include} snippets/04_using_srd.partial.md
:relative-images:
```

<!-- Note that we cannot include this anchor in the `partial` file as it would then appear in two different files-->

(role_researcher_user_guide_shared_storage)=

```{include} snippets/05_share_files.partial.md
:relative-images:
```

```{include} snippets/06_cocalc.partial.md
:relative-images:
```

```{include} snippets/07_gitlab.partial.md
:relative-images:
```

```{include} snippets/08_codimd.partial.md
:relative-images:
```

## {{unlock}} Access additional SRDs

Your project might make use of further SRDs in addition to the main shared desktop.
Usually this is because of a requirement for a different type of computing resource, such as access to one or more GPUs (graphics processing units).

You will access this machine in a similar way to the main shared desktop, by selecting a different `Desktop` connection.

````{note}
Our example user, Ada Lovelace, participating in the `sandbox` project at a Turing Data Study Group, might select `Ubuntu1_CPU2_8GB (Desktop)` instead of `Ubuntu0_CPU2_8GB (Desktop)`
```{image} user_guide/guacamole_dashboard.png
:alt: Research environment dashboard
:align: center
```
````

- This will bring you to the normal login screen, where you use the same `username` and `password` credentials as before.
- Any local files that you have created in the `/output/` folder on other VMs (e.g. analysis scripts, notes, derived data) will be automatically available in the new VM.

```{tip}
The naming pattern of the available desktop connections lets you know their compute capabilities.
For example `Ubuntu1_CPU2_8GB` has 2 CPUs and 8GB of RAM.
```

```{include} snippets/10_databases.partial.md
:relative-images:
```

```{include} snippets/11_report_bugs.partial.md
:relative-images:
```

```{include} snippets/12_end_matter.partial.md
:relative-images:
```
