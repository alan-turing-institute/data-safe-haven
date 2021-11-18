## {{pray}} Acknowledgments

This user guide is based on an initial document written in March/April 2018 by Kirstie Whitaker.

Updates:

- December 2018 by Catherine Lawrence, Franz Király, Martin O'Reilly, and Sebastian Vollmer.
- March/April 2019 by Miguel Morin, Catherine Lawrence, Alvaro Cabrejas Egea, Kirstie Whitaker, James Robinson and Martin O'Reilly.
- November 2019 by Ben Walden, James Robinson and Daisy Parry.
- April 2020 by Jules Manser, James Robinson and Kirstie Whitaker.
- November 2021 by James Robinson

## {{passport_control}} Appendix A: Command Line Basics

If you have never used a Linux desktop before, you might find some of the following commands useful if you are using a terminal.

Go into a project directory to work in it

```bash
cd NAME-OF-PROJECT
```

Go back one directory

```bash
cd ..
```

List what’s in the current directory

```bash
ls
```

Create a new directory

```bash
mkdir NAME-OF-YOUR-DIRECTORY
```

Remove a file

```bash
rm NAME-OF-FILE
```

Remove a directory and all of its contents

```bash
rm -r NAME-OF-DIRECTORY
```

View command history

```bash
history
```

Show which directory I am in

```bash
pwd
```

Clear the shell window

```bash
clear
```

## {{notebook}} Appendix B: Gitlab tutorial notes

`GitLab` can be thought of as a local version of `GitHub` - that is a git server along with useful features such as:

- **Project wiki** - exactly what it says
- **Project pastebin** - share bits of code
- **Project issue tracker** - track things TODO and bugs
- **Pull requests** - Way to keep track of changes individuals have made to be included in master

Some teams design their entire workflows around these things.
A comparison in terms of features can be found [here](https://usersnap.com/blog/gitlab-github/).

### Getting started with Git

If you have never used `git` before, you might want to take a look at an introductory guide.
There are multiple `git` cheat sheets such as[this one from the JIRA authors](https://www.atlassian.com/git/tutorials/atlassian-git-cheatsheet) and [this interactive one](http://ndpsoftware.com/git-cheatsheet.html) and .

### Repositories

A repository is usually used to organize a single project.
Repositories can contain folders and files, images, videos, spreadsheets, and data sets – anything your project needs.
We recommend including a README, or a file with information about your project.
Over the course of the work that you do in your SRE, you will often be accessing and adding files to the same project repository.

### Add your Git username and set your email

It is important to configure your `git` username and email address, since every `git` commit will use this information to identify you as the author.
On your shell, type the following command to add your username:

```bash
git config --global user.name "YOUR_USERNAME"
```

Then verify that you have the correct username:

```bash
git config --global user.name
```

To set your email address, type the following command:

```bash
git config --global user.email "your_email_address@example.com"
```

To verify that you entered your email correctly, type:

```bash
git config --global user.email
```

You'll need to do this only once, since you are using the `--global` option.
It tells Git to always use this information for anything you do on that system.
If you want to override this with a different username or email address for specific projects, you can run the command without the `--global` option when you’re in that project.

### Cloning projects

In `git`, when you copy a project you say you "clone" it.
To work on a git project on the Linux Data Science desktop, you will need to clone it.
To do this, sign in to `GitLab`.

When you are on your Dashboard, click on the project that you’d like to clone.
To work in the project, you can copy a link to the `git` repository through a SSH or a HTTPS protocol.
SSH is easier to use after it’s been set up, [you can find the details here](https://docs.gitlab.com/ee/gitlab-basics/create-your-ssh-keys.html).
While you are at the Project tab, select HTTPS or SSH from the dropdown menu and copy the link using the Copy URL to clipboard button (you’ll have to paste it on your shell in the next step>).

```{image} user_guide/gitlab_clone_url.png
:alt: Clone GitLab project
:align: center
```

Go to your computer’s shell and type the following command with your SSH or HTTPS URL:

```bash
git clone <PASTE HTTPS OR SSH HERE>
```

### Branches

Branching is the way to work on different versions of a repository at one time.
By default your repository has one branch usually named `master` or `main` which is considered to be the definitive branch.
We use branches to experiment and make edits before committing them to `main`.

When you create a branch off the `main` branch, you’re making a copy, or snapshot, of `main` as it was at that point in time.
If someone else made changes to the `main` branch while you were working on your branch, you could pull in those updates.

To create a branch:

```bash
git checkout -b NAME-OF-BRANCH
```

Work on an existing branch:

```bash
git checkout NAME-OF-BRANCH
```

To merge the `main` branch into a created branch you need to be on the created branch.

```bash
git checkout NAME-OF-BRANCH
git merge main
```

To merge a created branch into the `main` branch you need to be on the created branch.

```bash
git checkout main
git merge NAME-OF-BRANCH
```

### Downloading the latest changes in a project

This is for you to work on an up-to-date copy (it is important to do this every time you start working on a project), while you set up tracking branches.
You pull from remote repositories to get all the changes made by users since the last time you cloned or pulled the project.
Later, you can push your local commits to the remote repositories.

```bash
git pull REMOTE NAME-OF-BRANCH
```

When you first clone a repository, REMOTE is typically `origin`.
This is where the repository came from, and it indicates the SSH or HTTPS URL of the repository on the remote server.
NAME-OF-BRANCH is usually `main`, but it may be any existing branch.

### Add and commit local changes

You’ll see your local changes in red when you type `git status`.
These changes may be new, modified, or deleted files/folders.
Use `git add` to stage a local file/folder for committing.
Then use `git commit` to commit the staged files:

```bash
git add FILE OR FOLDER
git commit -m "COMMENT TO DESCRIBE THE INTENTION OF THE COMMIT"
```

To add and commit all local changes in one command:

```bash
git add .
git commit -m "COMMENT TO DESCRIBE THE INTENTION OF THE COMMIT"
```

To push all local commits to the remote repository:

```bash
git push REMOTE NAME-OF-BRANCH
```

For example, to push your local commits to the `main` branch of the origin remote:

```bash
git push origin main
```

To delete all local changes in the repository that have not been added to the staging area, and leave unstaged files/folders, type:

```bash
git checkout .
```

**Note:** The . character typically means all in Git.

### How to create a Merge Request

Merge requests are useful to integrate separate changes that you’ve made to a project, on different branches.
This is a brief guide on how to create a merge request.
For more information, check the [merge requests documentation](https://docs.gitlab.com/ee/user/project/merge_requests/index.html).

- Before you start, you should have already created a branch and pushed your changes to `GitLab`.
- Go to the project where you’d like to merge your changes and click on the `Merge requests` tab.
- Click on `New merge request` on the right side of the screen.
- From there on, you have the option to select the source branch and the target branch you’d like to compare to.

The default target project is the upstream repository, but you can choose to compare across any of its forks.

```{image} user_guide/gitlab_new_merge_request.png
:alt: New GitLab merge request
:align: center
```

- When ready, click on the Compare branches and continue button.
- At a minimum, add a title and a description to your merge request.
- Optionally, select a user to review your merge request and to accept or close it. You may also select a milestone and labels.

```{image} user_guide/gitlab_merge_request_details.png
:alt: GitLab merge request details
:align: center
```

- When ready, click on the `Submit merge request` button.

Your merge request will be ready to be approved and merged.

## {{microscope}} Appendix C: Troubleshooting

### {{exclamation}} No applications available

#### Symptom

- You can successfully log into the remote desktop web interface

```{note}
For our example user, Ada Lovelace, this would be `https://sandbox.projects.turingsafehaven.ac.uk` .
```

- You do not see any available connections

  ```{image} user_guide/msrds_no_work_resources.png
  :alt: No connections available
  :align: center
  ```

#### Cause

You have not been added to the correct SRE security group.

#### Solution

Ask your {ref}`System Manager <role_system_manager>` to add you to the appropriate SRE security group.

### {{exclamation}} Unexpected certificate error

#### Symptom

- You can successfully log into the remote desktop web interface

  ```{note}
  For our example user, Ada Lovelace, this would be `https://sandbox.projects.turingsafehaven.ac.uk`.
  ```

- You can see several apps, but when you try to launch one of them, you receive an error saying "Your session ended because an unexpected server authentication certificate was received from the remote PC."
- When you click on the padlock icon in the address bar and view the SSL certificate, the "SHA-1 Fingerprint" in the certificate matches the "SHA-1 Thumbprint" in the error message.

  ```{image} user_guide/msrds_unexpected_certificate_error.png
  :alt: Unexpected certificate error
  :align: center
  ```

#### Cause

The SSL certificate protecting your connection to the RDS webclient expires every three months and is renewed every two months.
The new SSL certificate is seamlessly picked up by your browser when connecting to the web page.
However, the webclient downloads a separate copy of the certificate for its own use to validate connections to the apps it serves.
This downloaded certificate is cached by your browser, which means that the old certificate will continue to be used by the web app when the browser is allowed to load things from its cache.

#### Solution

Get your browser to do a [hard reload](https://www.getfilecloud.com/blog/2015/03/tech-tip-how-to-do-hard-refresh-in-browsers/) of the page (instructions vary by browser and operating system).
You may also need to [clear your cache](https://www.refreshyourcache.com/en/home/) for this site.
In either case, removing locally cached data should mean that you retrieve a copy of the new certificate.
