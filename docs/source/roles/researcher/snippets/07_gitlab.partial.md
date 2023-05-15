## {{pill}} Versioning code using GitLab

`GitLab` is a code hosting platform for version control and collaboration - similar to `GitHub`.
It allows you to use `git` to **version control** your work, coordinate tasks using `GitLab` **issues** and review work using `GitLab` **merge requests**.

```{note}
`GitLab` is a fully open source project.
This information doesn't matter at all for how you use `GitLab` within the SRE, but we do want to thank the community for maintaining free and open source software for us to use and reuse.
You can read more about `GitLab` at [their code repository](<https://gitlab.com/gitlab-org/gitlab>).
```

The `GitLab` instance within the SRE can contain code, documentation and results from your team's analyses.
You do not need to worry about the security of the information you upload there as it is fully contained within the SRE and there is no access to the internet and/or external servers.

```{important}
The `GitLab` instance within the SRE is entirely separate from the https://gitlab.com service.
```

### {{books}} Maintaining an archive of the project

The Data Safe Haven SRE is hosted on the Microsoft Azure cloud platform.
One of the benefits of having cloud based infastructure is that it can be deleted forever when the project is over.
Deleting the infrastructure ensures that neither sensitive data nor insights derived from the data or modelling techniques persist.

Make sure that every piece of code you think might be useful is stored in a `GitLab` repository within the secure environment.
Any other work should be transferred to the shared `/shared/` drive.
Anything that you think should be considered for **egress** from the environment (eg. images or processed datasets) should be transferred to the shared `/output/` drive.

```{caution}
If you are participating in a Turing Data Study Group, everything that is not stored in a GitLab repository or on the shared `/shared/` or `/output/` drives by Friday lunchtime will be **DESTROYED FOR EVER**.
```

### {{unlock}} Access GitLab

You can access `GitLab` from an internet browser in the SRD using the desktop shortcut.
Login with username `firstname.lastname` (the domain is not needed) and `password` .

````{note}
Our example user, Ada Lovelace would enter `ada.lovelace` in the `LDAP Username` box, enter her password and then click `Sign in` .

```{image} user_guide/gitlab_screenshot_login.png
:alt: GitLab login
:align: center
```
````

Accessing `GitLab` from the browser on the SRD is an easy way to switch between analysis work and documenting the process or results.

```{warning}
Do not use your username and password from a pre-existing `GitLab` account!
The `GitLab` instance within the SRE is entirely separate from the https://gitlab.com service and is expecting the same username and password that you used to log into the SRE.
```

### {{open_hands}} Public repositories within the SRE

The `GitLab` instance inside the secure research environment is entirely contained _inside_ the SRE.

When you make a repository inside the SRE "public" it is visible to your collaborators who also have access to the SRE.
A "public" repository within the SRE is only visible to others with the same data access approval, it is not open to the general public via the internet.

```{tip}
We recommend that you make your repositories public to facilitate collaboration within the secure research environment.
```

### {{construction_worker}} Support for GitLab use

If you have not used GitLab before:

- There is a small tutorial available as an [Appendix](#appendix-b-gitlab-tutorial-notes) to this user guide.
- You can find the official documentation on the [GitLab website](https://docs.gitlab.com/ee/gitlab-basics/).
- Ask your team mates for help.
- Ask the designated contact for your SRE.
- There may be a dedicated discussion channel, for example during Turing Data Study Groups you can ask in the Slack channel.
