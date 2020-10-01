# Learn more about the Safe Haven

## Overview

We provide an overview of the Data Safe Haven project.

+ [Azure implementation overview](overview/azure-implementation-details.md) - A technical overview of the Safe Haven architecture on Azure.

## Data handling

We present our processes for classifying data, which is necessary to determine the security tier of a work package.

+ [Data classification overview](classification/classification-overview.md) - A full overview of the data classification process, including the related technical and policy decisions.
+ [Unconsented patient data](classification/unconsented_data.md) - An overview of some considerations that must be taken into account when dealing with unconsented patient data.

## Security

We detail various design decisions that impact the security of our Safe Haven implementation. This includes reasoning for our different choices but also highlights potential limitations for our Safe Havens and how this may affect things like cyber security.

+ [Security controls](security_decisions/security-controls.md) - Documentation on the physical resilience of the Safe Haven and our design decisions involved.
+ [Safe Haven resilience](security_decisions/physical_resilence_and_availability.md) - Documentation on the physical resilience of the Safe Haven and our design decisions involved.

## Handling data

We detail our processes for moving data into (ingress) and out of (egress) the Safe Haven.

+ [Data and software ingress](ingress_and_egress/ingress.md) - An overview of the process for bringing data or software into the environment
+ [Data and software egress](ingress_and_egress/egress.md) - An overview of the process for bringing data or software out of the environment
