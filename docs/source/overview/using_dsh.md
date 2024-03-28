(using_dsh)=

# Before using the Data Safe Haven

This page contains some important considerations you must take before using the Data Safe Haven.
Where appropriate, there are links to external resources, including policies and processes used at The Turing.

```{warning}
Use of a Data Safe Haven is not by itself sufficient to guarantee the security of your data! It must be paired with appropriate information governance requirements and user agreements.
```

```{warning}
Each organisation deploying their own instance of the Data Safe Haven is responsible for verifying their Data Safe Haven instance is deployed as expected and that the deployed configuration effectively supports their own information governance policies and processes.

Each organisation deploying their own instance of the Data Safe Haven is responsible for verifying that the instance is configured as expected. The organisation is also reponsible for confirming that the deployed configuration is appropriate for their purposes and effectively supports their own information governance policies and processes. We provide the Data Safe Haven code and material on an ‘as is’ basis without warranties of any kind and you use the code and supporting materials at your own cost and risk.
```

```{tip}
In terms of the [Five Safes framework](https://ukdataservice.ac.uk/help/secure-lab/what-is-the-five-safes-framework/) the Data Safe Haven is aiming to be a Safe Setting.
```

## What is needed to run a Data Safe Haven?

The code of this project is not on its own sufficient to operate a secure environment for research on sensitive data.
In fact, _any_ functional TRE is not just code and infrastructure, but also people, policies, and processes.
This project provides code to deploy a TRE with a particular architecture and the documentation gives instructions and advice for operating an instance.
Every group deploying the Data Safe Haven will need to provide the rest including,

- Information governance processes
    - How to approve data ingress and egress
    - Classifying work into Data Safe Haven tiers
- Mapping internal roles or people to Data Safe Haven roles
- Staffing essential roles such as system and programme managers
- Data security incident handling procedures
- Financial planning
- Supporting infrastructure such as
    - Communication channels
    - Domains and DNS
    - Secure methods to share SAS tokens
    - Programme management tools

The [Standard Architecture for Trusted Research Environments (SATRE)](https://satre-specification.readthedocs.io) project is a useful reference for TRE design.
It features a comprehensive set of requirements, technical and non-technical, that a TRE operator should meet.
An evaluation of the Data Safe Haven production instances at the Turing against SATRE can be found [here](https://satre-specification.readthedocs.io/en/stable/evaluations/alan_turing_institute.html).

## Tiering

[Tiering](sensitivity_tiers.md) is a fundamental part of DSH.
The code deploys Secure Research Environments with four levels of technical control to meet five tiers of sensitivity classification.
These tiers are explained in the section [](design_security_objectives).

Each organisation will need to decide how to use the available tiers and a process to decide what tier is appropriate for each project.
This will require a careful consideration of the organisations risk appetite, balancing the value of enabling work against the risks of data disclosure.

The project classification process used at the Turing is described [here](https://alan-turing-institute.github.io/trusted-research/tasks/setting_up_tre/project_initialisation/project_classification.html).
This process considers work packages, which cover the combination of all input data and the planned work when making a classification.
That approach better captures the risks associated with merging data sets and also considers the sensitivity of intended outputs.

## Role mapping

The Data Safe Haven is designed with a number of [roles](roles) required for secure operation.
Importantly, some of these roles are mutually exclusive.
That is because one person holding multiple roles may circumvent security controls.
For example, a Researcher should not also be a System Manager as they would be able to conduct data ingress and egress, mock other users or create new user accounts.

These roles are specific to the Data Safe Haven.
Organisations will need to decide how to map their existing roles to Data Safe Haven roles or how to otherwise popular them.

## Bad actors

The technical controls of the Data Safe Haven cannot protect you completely against bad actors.
There are sensible restrictions to limit what users able to do.
For example, outbound network connection is strictly controlled to prevent users uploading sensitive data to the public internet.
However, the design assumes that users are generally trustworthy and good actors.
It is therefore necessary to have confidence in the identity of users and make a decision on whether to trust them.

TRE operators should consider how they balance different types of risk.
The [Five Safes framework](https://ukdataservice.ac.uk/help/secure-lab/what-is-the-five-safes-framework/) is useful for addressing this.
If you have low confidence in the safety of people, for example untrusted users, you will need to compensate in other areas.

## At the Turing

Our production instances of the Data Safe Haven are managed by a dedicated team at the Turing.
There processes and policies are open and can be read [here](https://alan-turing-institute.github.io/trusted-research).
The Turing provides no guarantee for anyone following its processes and assumes no responsibility for others running a Data Safe Haven instance.
Organisations must carefully consider the risks themselves and decide what is acceptable to them.
