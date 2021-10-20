# Policies

```{toctree}
:hidden: true
:glob:
:maxdepth: 2

data_sensitivity_classification/*
data_transfer/*
security/*
```

In this section we describe the data governance and user management policies that are used by the Safe Haven deployed at the Alan Turing Institute.
Please note that these may be incompatible with your organisation's existing procedures and so they are presented here as recommendations, not requirements.

Note that this is not a complete description of the Institute's core enterprise information security practices, which are described elsewhere.
Nor do we cover the data-centre level or organisational management security practices which are fundamental to any secure computing facility, but rely on the compliance of our data centre providers with ISO 27001 (Information Security Management System Requirements).

## Data transfer

- [Ingress of data or software](data_transfer/ingress.md) - Bringing code or data into the SRE
- [Egress of data, software or other results](data_transfer/egress.md) - Extracting code, data or other results from the SRE

## Classifying sensitive data

One of the major drivers for usability or security problems is over- or under-classification, that is, treating data as more or less sensitive than it deserves.
Regulatory and commercial compliance requirements place constraints on the use of datasets; implementation of that compliance must be set in the context of the threat and risk profile and balanced with researcher productivity.

Security can almost always be improved by adding additional barriers but these improvements almost always carry a cost in usability and performance.
As a result, misclassification is seriously costly for research organisations and their partners.

Overclassification results not just in lost researcher productivity, but also a loss of scientific engagement, as researchers choose not to take part in a project with cumbersome security requirements.
Systematic overclassification increases data risk by encouraging workaround breach.
The risks of under-classification include not only legal and financial sanction, but the loss of the social licence to operate of the whole community of data science researchers.

Within this context, the Alan Turing Institute has developed a tiered sensitivity system for classifying projects that use sensitive data.

- [Sensitivity tiers](data_sensitivity_classification/sensitivity_tiers.md) - Details of the five sensitivity tiers that projects are classified into
- [Classification process](data_sensitivity_classification/classification_process.md) - How to classify a project into one of our sensitivity tiers
- [Unconsented patient data](data_sensitivity_classification/unconsented_data.md) - An overview of some considerations that must be taken into account when dealing with unconsented patient data.

## Security guides

The Safe Haven provides a set of default security controls and policies.
Any organisation choosing to deploy a Safe Haven is, of course, free to adapt these defaults to fit their own requirements.

- [Technical controls](security/technical_controls.md) - A list of the technical controls that are applied by default
- [Security policies](security/security_policies.md) - A list of the security policies that we recommend
- [Software package approval policy](security/software_package_approval_policy.md) - Policy for approving software packages and the criteria for including them in the DSVM image
