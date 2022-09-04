# Design

```{toctree}
:hidden: true
:maxdepth: 2

architecture/index.md
security_decisions/index.md
```

## Decisions and constraints

We detail various decisions and constraints that have impacted the design of the Data Safe Haven.
This includes reasoning for our choices but also highlights potential limitations of our design and how this might affect things like security.
In addition to describing the architecture and technical security controls configured when deploying a Data Safe Haven following our deployment guide, we also share some of the information governance policies and processes we use to manage the security of our Data Safe Haven Instance.

```{warning}
Each organisation deploying their own instance of the Data Safe Haven is responsible for verifying their Data Safe Haven instance is deployed as expected and that the deployed configuration effectively supports their own information governance policies and processes.
```

[Architecture](architecture/index.md)
: How the Data Safe Haven infrastructure is designed.

[Security](security_decisions/index.md)
: Decisions about data security and the default controls at each SRE tier.
