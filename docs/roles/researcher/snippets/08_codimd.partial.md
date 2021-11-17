## {{book}} Collaborate on documents using CodiMD

`CodiMD` is a locally installed tool that allows you to collaboratively write reports.
It uses `Markdown` which is a simple way to format your text so that it renders nicely in full HTML.

```{note}
`CodiMD` is a fully open source version of the `HackMD` software.
This information doesn't matter at all for how you use `CodiMD` within the SRE, but we do want to thank the community for maintaining free and open source software for us to use and reuse.
You can read more about `CodiMD` at [their GitHub repository](<https://github.com/hackmdio/codimd#codimd>).
```

We recommend [this Markdown cheat sheet](<https://github.com/adam-p/markdown-here/wiki/Markdown-Cheatsheet>).

### {{unlock}} Access CodiMD

You can access `CodiMD` from an internet browser from the Linux Data Science Desktop using the desktop shortcut.
Login with your long-form username `firstname.lastname@<username domain>` and `password`.

````{note}
Our example user, Ada Lovelace would enter `ada.lovelace@projects.turingsafehaven.ac.uk` in the `Username` box, enter her password and then click `Sign in` .

```{image} user_guide/codimd_logon.png
:alt: CodiMD login
:align: center
```
````

Accessing CodiMD from the browser on the Linux Data Science Desktop is an easy way to switch between analysis work and documenting the process or results.

### {{busts_in_silhouette}} Editing other people's documents

The CodiMD instance inside the secure research environment is entirely contained *inside* the SRE.

When you make a markdown document inside the SRE "editable" your collaborators who also have access to the SRE can access it via the URL at the top of the page.
They will have the right to change the file if they are signed into the CodiMD instance.

The link will only work for people who have the same data access approval, it is not open to the general public via the internet.

```{image} user_guide/codimd_access_options.png
:alt: CodiMD access options
:align: center
```

```{tip}
We recommend that you make your documents **editable** to facilitate collaboration within the secure research environment.
Alternatively, the **locked** option allows others to read but not edit the document.
```

The default URL is quite long and difficult to share with your collaborators.
We recommend **publishing** the document to get a much shorter URL which is easier to share with others.

Click the `Publish` button to publish the document and generate the short URL.
Click the pen button (shown in the image below) to return to the editable markdown view.

```{image} user_guide/codimd_publishing.png
:alt: CodiMD publishing
:align: center
```

```{important}
Remember that the document is not published to the internet, it is only available to others within the SRE.
```

```{tip}
If you are attending a Turing Data Study Group you will be asked to write a report describing the work your team undertook over the five days of the projects.
Store a copy of the CodiMD URL in a text file in the outputs folder.
You will find some example report templates that outline the recommended structure.
We recommend writing the report in CodiMD - rather than GitLab - so that everyone can edit and contribute quickly.
```

### {{microscope}} Troubleshooting CodiMD

We have noticed that a lower case `L` and an upper case `I` look very similar and often trip up users in the SRE.

```{tip}
Double check the characters in the URL, and if there are ambiguous ones try the one you haven't tried yet!
```

Rather than proliferate lots of documents, we recommend that one person is tasked with creating the file and sharing the URL with other team members.

```{tip}
You could use the GitLab wiki or `README` file to share links to collaboratively written documents.
```

