# Introduction

```{toctree}
:hidden: true
:maxdepth: 2
```

This documentation requires no prior knowledge and is a good place to start.

## What is a Safe Haven?

Secure environments for analysis of sensitive datasets are essential for research.
These environments are variously known as "data safe havens" or "trusted research environments" (TREs).

It is essential that sensitive or confidential datasets are kept secure.
This is helps ensure that the data analysis complies with data protection laws.
It also forms part of the "social licence" to carry out these analyses ethically and for worthwhile reasons.

Creating and operating environments which are safe, efficient, productive and collaborative is a difficult task.
Decisions need to be made about the technical and policy requirements and how to enforce them.

## Why might you use the Data Safe Haven?

The Data Safe Haven is our implementation of a TRE following the principles we laid out in an [earlier paper](https://arxiv.org/abs/1908.08737).

Since increasing security inevitably decreases usability, we classify projects into one of five security tiers.
As the sensitivity of the data increases, the security controls applied at that tier tighten.
We propose choices for the security controls that should be applied in the areas of:

- data classification
- data and software ingress (data or code entering a secure environment from an external source)
- data and software egress (data or code leaving a secure environment to an external recipient)
- user access
- user device management
- analysis environments

The Data Safe Haven provides a set of instructions that will allow you to set up your own secure environment with appropriate security controls.
Our aim throughout has been to make the environments reproducible, usable, secure, cloud-native and open source.

```{admonition} Reproducible
We use software tools to define our infrastructure.
This makes it easy to deploy an isolated secure environment for each project.
Our deployments are reproducible, since they rely on running scripts controlled by a single configuration file.
This gives configurability while minimising human error at deployment time.
```

```{admonition} Usable
We want to maximise the productivity of our users within the security constraints imposed by the sensitivity of the data with which they are working.
The primary user interface consists of one or more data analysis virtual machines.
These are Ubuntu desktop environments with many data science tools pre-installed.
They also have access to database and file storage and locally-hosted collaborative services such as GitLab.
```

```{admonition} Secure
Role-based access controls are used to determine which users can perform which actions.
Connectivity is kept to a minimum between different parts of the Data Safe Haven and outwards to the wider internet.
```

```{admonition} Cloud-native
The scalability and resilience of modern cloud-computing providers allows anyone to easily use our code to deploy their own Safe Haven.
Currently, we only support Microsoft Azure, but we are hoping to look at other providers in future.
```

```{admonition} Open source
The Data Safe Haven is released under the [MIT licence](https://opensource.org/licenses/MIT).
This means that that any person or organisation is welcome to extend the code base and adapt it to their particular context.
```

## Is the Data Safe Haven suitable for you?

The Data Safe Haven was initially developed for use at the Alan Turing Institute.
It should be useful outside this context although you might need to make some alterations to fit your requirements.
We also hope that you will contribute any improvements back to the main project.

```{warning}
The Data Safe Haven is not a managed service. It is a set of instructions enabling you to set up your own secure environment
```
