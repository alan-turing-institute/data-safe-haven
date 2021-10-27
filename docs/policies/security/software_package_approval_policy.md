(policy_software_package_approval)=
# Software package approval policy

## Introduction

The secure research environments available in the Data Safe Haven have access to package repositories for certain supported languages: currently `PyPI (Python)` and `CRAN (R)`.
At Tier 3 and above, these mirrors do not include all of the packages available from the parent repository.
Instead they provide access to a subset of approved packages that have been vetted to mitigate the risk of introducing malicious or unsound software into the secure environment.

To improve the usability of the research environment, approved packages that are deemed broadly useful to a cross section of researchers are also included in the data science virtual machine (DSVM) image, making them directly available to all users without requiring installation from the package mirror.

This page sets out the policy for approving software packages and the criteria for including them in the DSVM image.
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

- package name squatting (approving a similarly-named package instead of the intended one)
- privilege escalation attacks (enabling a user to gain elevated access permissions).

(policy_security_package_approval)=

## Policy

- For each supported programming language, three package lists will be maintained:
  - an allowlist of packages that are available from the package mirrors deployed in Tier 3 secure environments
  - a core list of broadly useful packages from the allowlist that are included in the DSVM image
  - where applicable, a denylist of packages (with specific version numbers) that have been specifically rejected due to known security vulnerabilities or other issues.
- Users may request to add packages to the allowlist via the {ref}`procedure described below <policy_software_package_review_procedure>`.
  In the interests of improving researcher productivity the aim will be to accommodate such requests, provided there are no outweighing security concerns associated with the package or its dependencies.
- Requests will be reviewed by a safe haven administrator.
  When deciding whether to accept or reject a request, the reviewer will take into account:
  - information provided by the user when making the request
  - package author/contributor identities
  - any existing package/version denylist
  - relevant data on the package _and_ its full dependency tree including:
    - download statistics (recent and longer-term, current and previous versions)
    - publicly-accessible CVE databases (listing Common Vulnerabilities and Exposures)
- If approved, a requested package will be added to the Tier 3 package allowlist making it available to all future SRE deployments via the package mirror (as long as it remains on the allowlist).
- New additions to the allowlist will be judged against the {ref}`criteria for inclusion <policy_software_package_inclusion_criteria>` in the DSVM image and, where appropriate, also added to that list.
- The DSVM image will be updated every month to ensure that changes to the image package list are propagated to new safe haven deployments.

(policy_software_package_inclusion_criteria)=
### Criteria for inclusion in the DSVM image

Allowed software that is considered broadly useful to a cross section of researchers will be included in the DSVM image.

To meet this condition, a package should:

- implement at least one generic (i.e. not domain-specific) statistical algorithm or method
- OR provide support for a cross-cutting analysis technique (e.g. geospatial data analysis, NLP)
- OR facilitate data science or software development best practices (e.g. for robustness, correctness, reproducibility)
- OR enhance the presentational features of the programming language (e.g. for producing plots, notebooks, articles, websites)
- OR enhance the usability of the programming language or development environment (e.g. RStudio, PyCharm).

(policy_software_package_review_procedure)=
## Package request/review procedure

- A user requests a package by completing the {ref}`software package request form <software_package_request_form>`, including responses to the following questions:
  - Is this package the mostly widely supported for the intended purpose?
  - What will you be able to do with this package that you can't currently do? What alternatives are there?
  - What risks to data integrity/security might arise from including this package or its dependencies?
- A {ref}`role_system_manager` reviews the request according to the terms of the {ref}`approval policy <policy_security_package_approval>`.
- The reviewer adds their decision (accept/reject) to the form and notifies the user who made the request.
  - If the decision is to **reject**, the reviewer must include an explanation.
    Any subsequent request for the same package should address the specific concern raised.
  - If the decision is to **accept**, the reviewer forwards the request/review document to the data provider, who has the opportunity to question and/or overturn the decision.
- If approved, and no objection is received from the data provider, the package is added to the Tier 3 package allowlist.
