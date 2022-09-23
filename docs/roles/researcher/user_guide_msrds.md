(role_researcher_user_guide_msrds)=

# User Guide: Microsoft Remote Desktop

```{include} snippets/01_introduction.partial.md
:relative-images:
```

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

  - your `username`
  - your password

  then click `Sign in`.

  ````{note}
  Our example user, Ada Lovelace, participating in the `sandbox` project at a Turing Data Study Group, would enter `ada.lovelace` in the `User name` box, enter her password and then click `Sign in`.
  ```{image} user_guide/logon_environment_msrds.png
  :alt: Research environment log in
  :align: center
  ```
  ````

- If you are successful, you'll see the a screen with icons for the available apps.

  ```{image} user_guide/msrds_dashboard.png
  :alt: Research environment dashboard
  :align: center
  ```

  Welcome to the Data Safe Haven! {{wave}}

### {{penguin}} Log into the Secure Research Desktop

The primary method of performing data analysis in the SRE is using the Secure Research Desktop (SRD).

This is a virtual machine (VM) with many different applications and programming languages pre-installed on it.
Once connected to it, you can analyse the sensitive data belonging to your project while remaining completely isolated from the internet.

- Click on the `SRD Main (Desktop)` app to connect to the desktop.

  You will now **receive a call or mobile app notification** to authenticate using MFA.

  {{telephone_receiver}} For the call, you may have to move to an area with good reception and/or press the hash ( `#` ) key multiple times in-call.

  {{iphone}} For the app you will see a notification saying _"You have received a sign in verification request"_. Go to the app to approve the request.

  ```{image} user_guide/msrds_srd_connection.png
  :alt: SRD connection attempt
  :align: center
  ```

  ````{caution}
  If you don't respond to the MFA request quickly enough, or if it fails, you will likely get an error that looks like this:

  ```{image} user_guide/msrds_srd_connection_failure.png
  :alt: SRD connection failure
  :align: center
  ```
  You can try again by clicking "Reconnect".
  ````

- After verifying using MFA, you might get a security alert like this one. If you do, it is safe to tick the box and to click `Yes` .

  ```{image} user_guide/msrds_srd_security_fingerprint.png
  :alt: SRD security fingerprint
  :align: center
  ```

```{include} snippets/03_02_srd_login.partial.md
:relative-images:
```

```{include} snippets/04_using_srd.partial.md
:relative-images:
```

```{include} snippets/05_share_files.partial.md
:relative-images:
```

```{include} snippets/06_cocalc.partial.md
:relative-images:
```

```{tip}
You can also access `CoCalc` from the `CoCalc` icon on the `Work Resources` dashboard page.
```

```{include} snippets/07_gitlab.partial.md
:relative-images:
```

```{tip}
You can also access `GitLab` from the `GitLab` icon on the `Work Resources` dashboard page.
```

```{include} snippets/08_codimd.partial.md
:relative-images:
```

```{tip}
You can also access `CodiMD` from the `CodiMD` icon on the `Work Resources` dashboard page.
```

## {{unlock}} Access additional SRDs

Your project might make use of further SRDs in addition to the main shared desktop.
Usually this is because of a requirement for a different type of computing resource, such as access to one or more GPUs (graphics processing units).

You will access this machine in a similar way to the main shared desktop, but by using the `SRD Other (Desktop)` icon inside of the usual `SRD Main (Desktop)` icon.
You will need to know the IP address of the new machine, which you will be told by the designated contact for your SRE.

- When you click on the `SRD Other (Desktop)` icon you will see a screen asking you to identify the computer you wish to connect to.
- Enter the IP address of the desired SRD.

```{image} user_guide/msrds_srd_rdc_screen.png
:alt: SRD IP address input
:align: center
```

- After entering the IP address, you will get the normal login screen, where you use the same `username` and `password` credentials as before.
- Any local files that you have created in the `/output/` folder on other VMs (e.g. analysis scripts, notes, derived data) will be automatically available in the new VM.

```{include} snippets/10_databases.partial.md
:relative-images:
```

```{include} snippets/11_report_bugs.partial.md
:relative-images:
```

```{include} snippets/12_end_matter.partial.md
:relative-images:
```
