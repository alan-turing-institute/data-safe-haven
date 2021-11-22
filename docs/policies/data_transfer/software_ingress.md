# Software ingress

The base Data Safe Haven analysis environment provided in the secure research environments comes with a wide range of common data science software pre-installed.
We also provide access to certain package repositories for supported programming languages: currently `PyPI (Python)` and `CRAN (R)`.

For packages not available through a package mirror is provided, or for software which is not available from a package repository, an alternative method of software ingress must be provided.
This includes custom researcher-written code not available via the package mirrors (e.g. code available on a researcher's personal or institutional Github repositories).

For lower tier environments, the Data Safe Haven analysis environment has outbound access to the internet and software can be installed in the usual manner by either a normal user or an administrator as required.
For higher tier environments, the following software ingress options are available.

## Adding software to the default environment

If several researchers across multiple projects want to install the same tool, it makes sense to add it to the list of tools installed by default in the Data Safe Haven analysis environment.
The best way to do this is to open an issue on the [Data Safe Haven issue tracker](https://github.com/alan-turing-institute/data-safe-haven/issues).

```{admonition} Include this information in your issue
- Software name.
- Link to installation instructions.
- Justification: why is this tool useful across multiple projects.
```

## Adding software for a single project

If software is needed for a particular project and this requirement is known in advance then it might be possible to install this at deployment time.
In this case, software installation is performed while the virtual machine is outside of the Environment with outbound internet access available, but no access to any project data.
Once the additional software has been installed, the virtual machine is ingressed to the Environment via a one-way airlock.

Please contact your {ref}`role_system_manager` if you want to do this.

## Adding software to a running project

Once a virtual machine has been deployed into a secure analysis Environment, it cannot be moved outside of the Environment, as is has had access to the data in the Environment and therefore represents an unauthorised data egress risk.
As higher tier Environments do not have access to the internet, any additional software required must be brought into the Environment in order to be installed.

In this case, software is ingressed in a similar manner as data:

- Your {ref}`role_system_manager` will provide temporary **write-only** access to a software ingress volume
- Once the {ref}`role_researcher` transfers the software source or installation package to this volume, their access is revoked and the software is subject to a level of review appropriate to the Environment tier.
- Once any required review has been passed, the {ref}`role_system_manager` transfers the software into the environment.
  - For software that does not require administrative rights to install, the {ref}`role_researcher` can then install the software or transfer the source to a version control repository within the Environment as appropriate.
  - For software that requires administrative rights to install, a {ref}`role_system_manager` must run the installation process.
