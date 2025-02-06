# Managing allowlists

For Tier 3 SREs, the Python and R software packages that users are allowed to download from the PyPI and CRAN repositories are restricted.
Connection to PyPI and CRAN is achieved using [Sonatype Nexus Repository](https://www.sonatype.com/products/sonatype-nexus-repository).

Packages must be explicitly added to the allowlist for the relevant repository before the users can download the package.
Packages not on the allowlist are blocked.

An allowlist is a plain text file, with the name of each allowed package on its own line.

```{important}
The user must also be able to download any dependencies of any package on the allowlist.
You should ensure that any such dependencies are also added to the allowlist.

For example, a minimal CRAN allowlist that permits the user to install the packages `data.table`, `DBI`, and `RPostgres` would be as below.

:::{code} text
bit64
blob
data.table
DBI
hms
lubridate
RPostgres
withr
:::

This includes the requested packages and their dependencies.
```

## Viewing allowlists

To view the current allowlist for a given repository, use {typer}`dsh allowlist show`

```{code} shell
dsh allowlist show YOUR_SRE_NAME REPOSITORY_NAME
```

## Uploading and updating an allowlist

To upload an allowlist, use {typer}`dsh allowlist upload`.

```{code} shell
dsh allowlist upload YOUR_SRE_NAME PATH_TO_ALLOWLIST_FILE REPOSITORY_NAME
```

The local allowlist file does not need to have a specific name.

## Example allowlists

Example allowlists for PyPI and CRAN can be generated using {typer}`dsh allowlist template`

```{code} shell
dsh allowlist template REPOSITORY_NAME
```
