# Introduction

```{toctree}
:hidden: true
:maxdepth: 2
```

This documentation requires no prior knowledge and is a good place to start.

## What is a Safe Haven?

Secure environments for analysis of sensitive datasets are essential for research. Such environments, which are variously known as "data safe havens" or "trusted research environments" (TREs) are a vital part of the research infrastructure.

It is essential that sensitive or confidential datasets are kept secure, both to enable analysis of personal data in a manner that is capable of being compliant with data protection law, and to avoid jeopardising the consent of society for research activities with personal data (called 'social license').

To create and operate these environments safely and efficiently whilst ensuring usability, requires, as with many sociotechnical systems, a complex stack of interacting business process and design choices.
This document describes the approaches taken by the Alan Turing Institute when building and managing environments for productive, secure, collaborative research projects.

We propose choices for the security controls that should be applied in the areas of:

- data classification
- data ingress (data entering a secure Environment from an external source)
- data egress (data leaving a secure Environment to an external recipient)
- software ingress (software entering a secure Environment from an external source)
- user access
- user device management
- analysis environments

We do this for each of a small set of security "Tiers" - noting that the choice of security controls depends on the sensitivity of the data.

## Why might you use this Safe Haven?

In contrast to other TREs the Turing Data Safe Haven is not a service, but rather a set of instructions that will allow you to set up your own secure environment.
Our aim throughout has been to make the environments, reproducible, usable, secure, cloud-native and open source.

### Reproducible

Our approach - separately instantiating an isolated Environment for each project - is made feasible by the advent of "software-defined infrastructure".
It is now possible to specify a whole arrangement of IT infrastructure, servers, storage, access policies and so on, completely as **code**.
This code is executed against web services provided by infrastructure providers (the APIs of cloud providers such as Microsoft, Amazon or Google, or an in-house "private cloud" using a technology such as OpenStack), and the infrastructure instantiated.
Our model therefore assumes the availability of a software-defined infrastructure provision offering, in an ISO 27001 compliant data-centre and organisation, the scripted instantiation of virtual machines, storage, and secure virtual networks.

By treating infrastructure as code and relying on programatic setup and configuration of the Safe Haven, we ensure that our deployment is deterministically driven by running scripts which are controlled by a single common configuration file.
This achieves a balance between providing control over the configuration at deployment time and minimising human error when implementing security controls.

We also assume that "Identification, Authorisation and Authentication" (IAA) is available as a service from this provider, so that they provide user account creation, the creation of security groups, the assignment of users to security groups, the restriction of access to resources by such users, login challenge by password and a second factor, password reset, and other such security considerations.

A software-defined infrastructure platform on which to build, means that the definition of the Environment can be meaningfully audited - as no aspect of it is not described formally in code, it can be fully scrutinised.

### Usable

We want to maximise the productivity of our users within the security constraints imposed by the sensitivity of the data with which they are working.
The primary user interface consists of one or more data analysis virtual machines, Ubuntu desktop environments with many data science tools pre-installed, together with access to database and file storage and locally-hosted collaborative services such as GitLab.

### Secure

Authority to perform the particular operations allowed under the Turing Data Safe Haven data model is delegated using role-based access controls.
We try wherever possible to lock down connections between different parts of the Safe Haven or between the Safe Haven and the wider internet.

### Cloud-native

Making use of the scalability and resilience of modern cloud-computing providers allows anyone to easily use our code to deploy their own Safe Haven.
Currently, we only support Microsoft Azure, but we are hoping to look at other providers in future.

### Open source

The Turing Data Safe Haven is released under the MIT licence. This means that that any person or organisation is welcome to extend the code base and adapt it to their particular context.

## Is the Turing Safe Haven suitable for you?

The Data Safe Haven was developed for use at the Alan Turing Institute.
We do not offer a managed service, only the code that lets you deploy your own instance.
We hope that anyone who is interested in this project will make alterations to fit their own use case and will contribute any improvements back to the main project.

