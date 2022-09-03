(role_srd_available_software)=

# Available software

The Secure Research Desktops (SRDs) available in each SRE use the latest [Ubuntu LTS release](https://releases.ubuntu.com/).

- When a Data Safe Haven is first deployed a reference virtual machine image is created that uses the **latest available version** of each required software packages.
- Any packages installed using the `apt` package manager are further updated whenever a new desktop is deployed into any SRE.

The easiest way to update an SRD is by redeploying it - it may be possible for your {ref}`role_system_manager` to update software packages in-place but this is only recommended in the case of essential security fixes where the project cannot afford the downtime involved in a redeploy.

## Programming languages / compilers

```{include} snippets/software_languages.partial.md
:relative-images:
```

## Editors / IDEs

```{include} snippets/software_editors.partial.md
:relative-images:
```

## Writing / presentation tools

```{include} snippets/software_presentation.partial.md
:relative-images:
```

## Database access tools

```{include} snippets/software_database.partial.md
:relative-images:
```

## Other useful software

```{include} snippets/software_other.partial.md
:relative-images:
```
