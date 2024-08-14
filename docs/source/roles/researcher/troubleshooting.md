(roles_researcher_sre_troubleshooting)=

# Troubleshooting

## {{musical_keyboard}} Keyboard mapping

When you access the workspace you are actually connecting through the cloud to another computer - via a few intermediate computers/servers that monitor and maintain the security of the SRE.

:::{caution}
You may find that the keyboard mapping on your computer is not the same as the one set for the workspace.
:::

::::{admonition} Changing the keyboard layout
:class: dropdown note

From the workspace desktop, click on **{menuselection}`Applications --> Settings --> Keyboard`** to change the layout.

:::{tip}
We recommend opening an application that allows text entry (such as **Libre Office Writer** or a text editor) to check what keys the remote desktop thinks you're typing – especially if you need to use special characters.
:::
::::

## {{fox_face}} Firefox not responding

If you get an error message like this one about Firefox not responding, it is likely because you have a browser window open on another workspace.

:::{image} images/firefox_not_responding.png
:alt: Firefox not responding
:align: center
:::

Either log into that workspace and close Firefox, or follow the instructions [here](https://support.mozilla.org/en-US/kb/firefox-already-running-not-responding#w_remove-the-profile-lock-file) and delete your profile lock file.

:::{tip}
Your profile is likely stored under **~/snap/firefox/common/.mozilla/firefox**.
:::

## {{passport_control}} Command Line Basics

If you have never used a Linux desktop before, you might find some of the following commands useful if you are using a terminal.

::::{admonition} Changing directory
:class: dropdown note

Go into a project directory to work in it

:::{code} bash
cd NAME_OF_DIRECTORY
:::

Go back one directory

:::{code} bash
cd ..
:::
::::

::::{admonition} Finding out current status
:class: dropdown note

Show which directory I am in

:::{code} bash
pwd
:::

List what’s in the current directory

:::{code} bash
ls
:::

::::

::::{admonition} Creating/removing files and directories
:class: dropdown note

Create a new directory

:::{code} bash
mkdir NAME_OF_DIRECTORY
:::

Remove a file

:::{code} bash
rm NAME_OF_FILE
:::

Remove a directory and all of its contents

:::{code} bash
rm -r NAME_OF_DIRECTORY
:::
::::


::::{admonition} Miscellaneous
:class: dropdown note

View command history

:::{code} bash
history
:::

Clear text from the terminal window

:::{code} bash
clear
:::
::::

For a more detailed introduction, visit the official Ubuntu tutorial, [The Linux command line for beginners](https://ubuntu.com/tutorials/command-line-for-beginners)


(roles_researcher_gitea_basics)=

## {{notebook}} Gitea basics

**Gitea** can be thought of as a local version of **GitHub** - that is a git server along with useful features such as:

- **Project issue tracker** - track things TODO and bugs
- **Pull requests** - Way to keep track of changes individuals have made to be included in master

### Getting started with Git

If you have never used **git** before, you might want to take a look at an introductory guide.
There are multiple **git** cheat sheets such as [this one from the JIRA authors](https://www.atlassian.com/git/tutorials/atlassian-git-cheatsheet).

### Add your Git username and set your email

It is important to configure your username and email address, since every `git` commit will use this information to identify you as the author.

::::{admonition} Set your username
:class: dropdown note

- In your terminal, type the following command to add your username:

    :::{code} bash
    git config --global user.name "YOUR_USERNAME"
    :::

    :::{important}
    Use your **{ref}`short-form username <roles_researcher_username>`** here.
    :::

- Then verify that you have the correct username:

    :::{code} bash
    git config --global user.name
    :::

::::

::::{admonition} Set your email address
:class: dropdown note

- To set your email address, type the following command:

    :::{code} bash
    git config --global user.email "your_email_address@example.com"
    :::

- To verify that you entered your email correctly, type:

    :::{code} bash
    git config --global user.email
    :::
::::

### Repositories

A repository is usually used to organize a single project.
Repositories can contain folders and files, images, videos, spreadsheets, and data sets – anything your project needs.
We recommend including a README, or a file with information about your project.
Over the course of the work that you do in your SRE, you will often be accessing and adding files to the same project repository.


::::{admonition} Create a new repository
:class: dropdown note

- From the **Gitea** dashboard click on the **{guilabel}`+`** button next to the **Repositories** label.

    :::{image} images/gitea_new_repository.png
    :alt: Clone Gitea project
    :align: center
    :::

- Fill out the required information, with the following guidelines:
    - leave **Make repository private** unchecked
    - leave **Initialize repository** checked

::::

::::{admonition} Work on an existing repository
:class: dropdown note

- Sign into **Gitea** and click the **{guilabel}`Explore`** button in the top bar.

    :::{image} images/gitea_explore.png
    :alt: Explore Gitea repositories
    :align: center
    :::

- Click on the name of the repository you want to work on.

    :::{image} images/gitea_repository_view.png
    :alt: View Gitea repository
    :align: center
    :::

- From the repository view, click the **{guilabel}`HTTP`** button and copy the URL using the copy icon.
- From the terminal, type the following command

    :::{code} bash
    git clone URL_YOU_COPIED_FROM_GITEA
    :::

- This will start the process of copying the repository to the folder you are using in the terminal.

    :::{note}
    In **git**, copying a project is known as "cloning".
    :::
::::

### Branches

Branching is the way to work on different versions of a repository at one time.
By default your repository has one branch usually named **main** which is considered to be the definitive branch.
We use branches to experiment and make edits before committing them to **main**.

When you create a branch off the **main** branch, you’re making a copy, or snapshot, of **main** as it was at that point in time.
If someone else made changes to the **main** branch while you were working on your branch, you could pull in those updates.

::::{admonition} Working with branches
:class: dropdown note

- To create a new branch

    :::{code} bash
    git checkout -b BRANCH_NAME
    :::

- To switch to an existing branch

    :::{code} bash
    git checkout BRANCH_NAME
    :::

- To merge the **main** branch into a created branch (you need to first switch to the created branch).

    :::{code} bash
    git checkout BRANCH_NAME
    git merge main
    :::
::::

### Collaborating with others

This is for you to work on an up-to-date copy (it is important to do this every time you start working on a project), while you set up tracking branches.
You pull from remote repositories to get all the changes made by users since the last time you cloned or pulled the project.
Later, you can push your local commits to the remote repositories.

::::{admonition} Working with branches
:class: dropdown note

- To get the latest changes on a branch

    :::{code} bash
    git pull BRANCH_NAME
    :::

- To "commit" your local changes to your copy of the branch

    :::{code} bash
    git add FILES_OR_FOLDERS
    git commit -m "COMMENT TO DESCRIBE THE INTENTION OF THE COMMIT"
    :::

- To make your locally committed changes available to others using this branch

    :::{code} bash
    git push
    :::

- To delete all local changes in the repository that you have not yet committed

    :::{code} bash
    git checkout -- .
    :::
::::

Pull requests are a way to integrate your changes into a collaborative project.
For more information, check the **Gitea** [pull requests documentation](https://docs.gitea.com/next/usage/pull-request).

::::{admonition} Create a pull request in Gitea
:class: dropdown note

- Before you start, you should have already created a branch and pushed your changes.
- From the repository view in **Gitea**, click the **{guilabel}`Pull requests`** button.
- Click the **{guilabel}`New Pull Request`** button on the right side of the screen.

    :::{image} images/gitea_pull_request_start.png
    :alt: Gitea pull request
    :align: center
    :::

- Select the source branch and the target branch then click the **{guilabel}`New Pull Request`** button.

    :::{image} images/gitea_pull_request_diff.png
    :alt: Gitea pull request
    :align: center
    :::

- Add a title and description to your pull request then click the **{guilabel}`Create Pull Request`** button.

    :::{image} images/gitea_pull_request_finish.png
    :alt: Gitea pull request
    :align: center
    :::

Your pull request is now ready to be approved and merged.
::::

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
