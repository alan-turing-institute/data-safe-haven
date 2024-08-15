(roles_researcher_sre_troubleshooting)=

# Troubleshooting

## {{musical_keyboard}} Keyboard mapping

When you access the workspace you are actually connecting through the cloud to another computer - via a few intermediate computers/servers that monitor and maintain the security of the SRE.

:::{caution}
You may find that the keyboard mapping on your computer is not the same as the one set for the workspace.
:::

::::{admonition} Changing the keyboard layout
:class: dropdown note

- From the workspace desktop, click on **{menuselection}`Applications --> Settings --> Keyboard`** to change the layout.

    :::{tip}
    We recommend opening an application that allows text entry (such as **Libre Office Writer** or a text editor) to check what keys the remote desktop thinks you're typing – especially if you need to use special characters.
    :::
::::

## {{fox_face}} Firefox not responding

If you get an error message like this one about Firefox not responding, it is likely because you have a browser window open on another workspace.

:::{image} images/firefox_not_responding.png
:alt: Firefox not responding
:align: center
:width: 90%
:::

Either log into that workspace and close Firefox, or follow the instructions [here](https://support.mozilla.org/en-US/kb/firefox-already-running-not-responding#w_remove-the-profile-lock-file) and delete your profile lock file.

:::{tip}
Your profile is likely stored under **~/snap/firefox/common/.mozilla/firefox**.
:::

## {{zzz}} Idle screen lock

By default, the Xfce desktop will enter a screensaver and lock the screen after idling for five minutes.
This will require entering your password to unlock and is in addition to authenticating with Guacamole and the lock screen on your own computer.

You can disable the Xfce lock screen if you find it is unnecessary and slows your work.

:::{admonition} Disabling the lock screen
:class: dropdown note

- First, open Screensaver Preferences by either:
    - navigating to **{menuselection}`Applications --> Settings --> Screensaver Preferences`**
    - or running `xfce4-screensaver-preferences` on the command line.
- On the **Screensaver** tab you can disable the screensaver using the **Enable Screensaver** toggle.
- Alternatively, you can navigate to the **Lock Screen** tab to:
    - disable the lock screen with the **Enable Lock Screen** toggle
    - and/or disable locking when the screensaver runs with the **Lock Screen with Screensaver** toggle

:::

More information can be found in the [Xfce documentation](https://docs.xfce.org/apps/xfce4-screensaver/start).

### {{construction_worker}} Support for users

If you encounter problems while using the Data Safe Haven:

- Ask your team mates for help.
- Ask the designated contact for your SRE.
- There may be a dedicated discussion channel, for example a Slack/Teams/Discord channel or an email list.
- Consider reporting a bug if you think you've found a problem with the environment.

## {{bug}} Report a bug

The Data Safe Haven SRE has been developed in close collaboration with our users: you!

We try to make the user experience as smooth as possible and this document has been greatly improved by feedback from project participants and researchers going through the process for the first time.
We are constantly working to improve the SRE and we really appreciate your input and support as we develop the infrastructure.

:::{important}
If you find problems with the IT infrastructure, please contact the designated contact for your SRE.
:::

### {{wrench}} Help us to help you

To help us fix your issues please do the following:

- Make sure you have **read this document** and checked if it answers your query.
    - Please do not log an issue before you have read all of the sections in this document.
- Log out of the SRE and log back in again at least once
    - Re-attempt the process leading to the bug/error at least twice.
    - We know that "turn it off and turn it back on again" is a frustrating piece of advice to receive, but in our experience it works rather well! (Particularly when there are lots of folks trying these steps at the same time.)
    - The multi-factor authentication step in particular is known to have quite a few gremlins.
    - If you are getting frustrated, log out of everything, turn off your computer, take a 15 minute coffee break, and then start the process from the beginning.

- Write down a comprehensive summary of the issue.
- A really good bug report makes it much easier to pin down what the problem is. Please include:
    - Your computer's operating system and operating system version.
    - Precise condition under which the error occurs.
        - What steps would someone need to take to get the exact same error?
    - A precise description of the problem.
        - What happens? What would you expect to happen if there were no error?
    - Any workarounds/fixes you have found.

- Send the bug report to the designated contact for your SRE.

:::{hint}
We very strongly recommend "rubber ducking" this process before you talk to the designated contact for your SRE.
Either talk through to your imaginary rubber duck, or find a team member to describe the error to, as you write down the steps you have taken.
It is amazing how often working through your problem out loud helps you realise what the answer might be.
:::
