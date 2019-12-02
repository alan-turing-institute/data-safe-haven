
## Overview
We should ensure that all aspects of our data safe haven solution are deployable via scripts (i.e. our safe havens are defined by "infrastructure as code"). Many aspects of the security of our safe haven will depend on reliably reproducing one of a limited number of validated base configurations, with controlled and audited variations on these for specific instances (e.g. list of users, size and number of virtual machines, available storage etc). We should have a set of version controlled "master scripts" for deploying each base variation and also store the instance specific specification variations in version control. The goal is to have an executable record of each safe haven instance we deploy, for both reproducibility and audit purposes. Running validated parameterised scripts rather than ad-hoc commands will also minimise the risk of inadvertently compromising the security of a safe haven instance on initial deployment or post-deployment modification (e.g. ensuring that all new resources deployed have the appropriate access controls).

## Available deployment tools
We consider the following set of tools for deployment and configuration of computational infrastructure.

- Ansible
- Azure Resource Management (ARM) templates
- Azure Powershell Command Line Interface (CLI) or Libraries
- Azure Python Command Line Interface (CLI) or Libraries
- Chef
- Fabric
- Puppet
- SaltStack
- Terraform

## Considerations
We would like our solution to have the following properties.

### Declarative rather than procedural
- A **procedural** approach to infrastructure deployment defines a "recipe" of steps to follow to generate a desired infrastructure state from the current state.
- A **declarative** approach to infrastructure deployment defines a "configuration" describing the desired infrastructure state **independent** of the current state.

A declarative approach is preferred for the following reasons:
- **Clarity** of infrastructure description: With a declarative approach, the latest deployed configuration clearly and completely describes the current state of the deployed infrastructure. With a procedural approach, the current state of the deployed infrastructure is the result of cumulatively applying a set of scripts adding, amending and deleting resources and can only be inferred by mentally running these update scripts.
- **Consistency** of deployment: With a procedural approach, the steps required to reach a desired deployed configuration depend on the current state of the deployment. Unless all instances of a given infrastructure are updated in lockstep, each instance will require different subsets of update scripts to be applied to bring it up to date with the current configuration. Even just deploying a "fresh" instance requires running the initial deployment script plus all subsequent updates in order. In contrast, with a declarative approach, the latest configuration can simply be deployed against all instances and they will be updated to match it.

### A focus on infrastructure orchestration
Many of the long-standing tools being considered have traditionally focussed on setting up and updating the configuration of existing physical or virtual machines, with support for **orchestrating** the deployment of virtual infrastructure added later as a secondary provision. We plan to use virtual machine images and docker to manage the configuration of compute resources, so orchestration of virtual infrastructure should be first class functionality in our chosen solution.
