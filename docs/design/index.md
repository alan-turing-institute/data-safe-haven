# Design

```{toctree}
:hidden: true
:maxdepth: 2

architecture/index.md
security_decisions/index.md
```

## Overview

Two assumptions about the research user community are critical to our design, related to usability and openness.

### Usability

We must consider not only accidental breach and deliberate attack, but also the possibility of "workaround breaches".
These involve well-intentioned researchers circumventing security measures in an attempt to make their data analysis easier, for example, by copying datasets to their personal device.
We expect that the user community will be relatively technically skilled and so the casual use of technical circumvention measures, not by adversaries but by colleagues, must be considered.
This can be mitigated by increasing awareness and placing inconvenience barriers in the way of undesired behaviours.

### Openness

Research institutions need to be open about the research they carry out, and hence, the datasets they hold.
This is because of both the need to publish research as part of impact cases to funders, and because of the need to maintain the trust of society, known as "social licence".
This means that the Data Safe Haven cannot rely on "security through obscurity", we must make our security decisions assuming that adversaries know what we have, what we are doing with it, and how we secure it.

## Decisions and constraints

We detail various decisions and constraints that have impacted the design of the Data Safe Haven.
This includes reasoning for our choices but also highlights potential limitations of our design and how this might affect things like security.

[Architecture](architecture/index.md)
: How the Data Safe Haven infrastructure is designed.

[Security](security_decisions/index.md)
: Decisions about data security and the default controls at each SRE tier.
