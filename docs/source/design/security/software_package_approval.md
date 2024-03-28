# Software approval policy

To maximise the usability of the secure research environments, we pre-install certain software packages that are deemed broadly useful to a cross section of researchers, thus making them available to all users.

Other software packages which are only of interest to a subset of users can be made available for download from remote package repositories.
Currently, we support PyPI (Python) and CRAN (R) as remote repositories.

For higher {ref}`sensitivity tiers <policy_classification_sensitivity_tiers>` ({ref}`policy_tier_3` and above), only a subset of packages are made available in this way.
This subset of packages constitutes an "allowlist" of packages that have been vetted to mitigate the risk of introducing malicious or unsound software into the secure environment.

```{warning}
The Data Safe Haven team manages a default allowlist, but individual deployments may be using their own versions.
Check with your {ref}`role_system_manager` what is being used in your case
```

This page sets out the policy for adding software packages to the default allowlist and/or software to the pre-installed software list.
It also describes the procedure that users of the secure environment should follow to request new additions to the allowlist.

## Background

Given the safeguards afforded by the safe haven environment, and the separation of responsibilities between its constituent resources, the level of risk associated with the introduction of third party software packages is considered low.
Moreover, access to the environment is carefully controlled and there is a presumption of trust in the individual researchers to whom access is granted.

Nevertheless, the introduction of any software into the safe haven must be considered against the potential risks of:

- approved users having access to data to which they shouldn't (e.g. from data mixing)
- unapproved users having access to data (e.g. from a data breach)
- poisoning of data and/or outputs
- resource misuse (allocation of computational resources for unintended or wasteful purposes).

Such risks may originate unwittingly, from a user who wants to "just get the job done", or from a user, network team member or administrator acting maliciously.

Specific risks which this policy aims to mitigate include:

- package name squatting (allowlisting a similarly-named package instead of the intended one)
- privilege escalation attacks (enabling a user to gain elevated access permissions)
- unauthorised data ingress (in particular, it is possible to upload arbitrary data to PyPI without review)

(package_inclusion_policy)=

## Policy

- For each supported repository, three package lists will be maintained:
    - a core allowlist of broadly useful packages that should be pre-installed in each environment
    - an extra allowlist of packages that may be useful for specific projects
    - an expanded list to be made available from the package repositories consisting of the core and extra packages plus their dependencies
- Users may request to add packages to these allowlists via the {ref}`package request procedure <package_request_procedure>`.
    - In the interests of improving researcher productivity the aim will be to accommodate such requests, provided there are no outweighing security concerns associated with the package or its dependencies.
- Requests will be reviewed by the project team using the information provided by the user when making the request
- If approved, a requested package will be added to either the core or extra allowlist (as appropriate)

(package_inclusion_criteria)=

### Criteria for inclusion in core

Only software that is considered broadly useful to a cross section of researchers should be included in core.

To meet this condition, a package should:

- implement at least one generic (i.e. not domain-specific) statistical algorithm or method, or
- provide support for a cross-cutting analysis technique (e.g. geospatial data analysis, NLP), or
- facilitate data science or software development best practices (e.g. for robustness, correctness, reproducibility), or
- enhance the presentational features of the programming language (e.g. for producing plots, notebooks, articles, websites), or
- enhance the usability of the programming language or development environment (e.g. RStudio, PyCharm)

(package_request_procedure)=

## Package request/review procedure

- A user requests a package by opening a `Software package request` issue on the Data Safe Haven GitHub repository, including responses to the following questions:
    - Is this package the mostly widely supported for the intended purpose?
    - What will you be able to do with this package that you can't currently do? What alternatives are there?
    - What risks to data integrity/security might arise from including this package or its dependencies?
- A member of the project team reviews the request according to the terms of the {ref}`package_inclusion_policy`.
- The reviewer adds their decision (accept/reject) to the issue and notifies the user who made the request.
    - If the decision is to reject, the reviewer must include an explanation. Any subsequent request for the same package should address the specific concern raised.
    - If the decision is to accept, a pull request should be made that will add the package to the appropriate list.
- Once the pull request is approved, system administrators of any running deployment can decide whether to update to the new allowlist definitions.
