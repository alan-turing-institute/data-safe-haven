(role_dsvm_available_software)=

# Available software

The data science desktops available in each SRE use the latest [Ubuntu LTS release](https://wiki.ubuntu.com/Releases).

- When a Data Safe Haven is first deployed a reference virtual machine image is created that uses the **latest available version** of each required software packages.
- Any packages installed using the `apt` package manager are further updated whenever a new desktop is deployed into any SRE.

The easiest way to update a data science desktop is by redeploying it - it may be possible for your {ref}`role_system_manager` to update software packages in-place but this is only recommended in the case of essential security fixes where the project cannot afford the downtime involved in a redeploy.

## Programming languages

- `Microsoft .NET` framework
- `gcc` compilers
- `Java`
- `Julia` (plus common data science libraries)
- `Python` [three most recent versions] (plus common data science libraries)
- `R` (plus common data science libraries)
- `scala`
- `spark-shell`

## Editors/IDEs

- `atom`
- `emacs`
- `nano`
- `PyCharm`
- `RStudio`
- `vim`
- `Visual Studio Code`

## Presentation tools

- `LaTeX`
- `LibreOffice`

## Development/data science tools

- `Azure Data Studio`
- `DBeaver`
- `Firefox`
- `git`
- `psql`
- `sqlcmd`
- `weka`
