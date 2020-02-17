# Data Safe Haven


Welcome to the Data Safe Havens project. This repository contains the code necessary to deploy an instance of the Alan Turing Institute's Data Safe Haven, and instructions on how to use it.


## What is a Data Safe Haven


Secure environments for analysis of sensitive datasets are essential for research. Data Safe Havens provide a way to build a secure environment for data analysis.


[Overview](docs/processes/provider-overview.md) - Find out more about Data Safe Havens, and how to use our model.

[Implementation on Azure](docs/processes/provider-azure-implementation-details.md) - A technical overview of the Safe Haven architecture on Azure.


## Setting up a Data Safe Haven


You can set up a data safe haven yourself.


[Safe Haven Management](safe_haven_management_environment/azure-runbooks/shm_build_instructions.md) - Instructions on how to build a Safe Haven Management environment in Azure.

[Secure Research Environment](secure_research_environment/azure-runbooks/sre_build_instructions.md) - Instructions on how to build a Secure Research Environment in Azure.

[Azure VMs](vm_image_management/README.md) - Instructions on how to build the VM image that is used for data analysis in your secure environment.

[Create New Users](secure_research_environment/create-users/README.md) - Create and add new users to Data Safe Haven environments.

[Data Ingress](docs/processes/provider-data-ingress.md) - Instructions for data providers, on how to transfer data into a safe haven for secure analysis.

Before you go ahead to set up a Data Safe Haven, you'll need to have the following pre-requisites:
- `Powershell`
    - needed to deploy infrastructure
- `bash`
    - needed to deploy infrastructure
- `Microsoft Azure` account
    - target for infrastructure deployment


[Design choices](docs/design/overview.md) - You can find out more about the design of Data Safe Havens here.


## Using a Data Safe Havens


Once a Safe Haven environment has been set up for a project, you can get access to it to carry out secure research.


[Data Classification User Guide](docs/safe_haven_webapp_user_guide.md) - Step by Step instructions on classify project data using our classification WebApp.

[Safe Havens Cheat Sheet]docs/safe-haven-user-cheat-sheet.md) - Quick instructions on how to get set up on a Safe Haven environment.

[Safe Havens User Guide](docs/safe_haven_user_guide.md) - Step by Step instructions on how to get set up on a Safe Haven environment.

## The philosophy of our Safe Haven design

We should ensure that all aspects of our data safe haven solution are deployable via scripts (i.e. our safe havens are defined by "infrastructure as code"). Many aspects of the security of our safe haven will depend on reliably reproducing one of a limited number of validated base configurations, with controlled and audited variations on these for specific instances (e.g. list of users, size and number of virtual machines, available storage etc). We should have a set of version controlled "master scripts" for deploying each base variation and also store the instance specific specification variations in version control. The goal is to have an executable record of each safe haven instance we deploy, for both reproducibility and audit purposes. Running validated parameterised scripts rather than ad-hoc commands will also minimise the risk of inadvertently compromising the security of a safe haven instance on initial deployment or post-deployment modification (e.g. ensuring that all new resources deployed have the appropriate access controls).

### Available deployment tools
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

### Considerations
We would like our solution to have the following properties.

#### Declarative rather than procedural
- A **procedural** approach to infrastructure deployment defines a "recipe" of steps to follow to generate a desired infrastructure state from the current state.
- A **declarative** approach to infrastructure deployment defines a "configuration" describing the desired infrastructure state **independent** of the current state.

A declarative approach is preferred for the following reasons:
- **Clarity** of infrastructure description: With a declarative approach, the latest deployed configuration clearly and completely describes the current state of the deployed infrastructure. With a procedural approach, the current state of the deployed infrastructure is the result of cumulatively applying a set of scripts adding, amending and deleting resources and can only be inferred by mentally running these update scripts.
- **Consistency** of deployment: With a procedural approach, the steps required to reach a desired deployed configuration depend on the current state of the deployment. Unless all instances of a given infrastructure are updated in lockstep, each instance will require different subsets of update scripts to be applied to bring it up to date with the current configuration. Even just deploying a "fresh" instance requires running the initial deployment script plus all subsequent updates in order. In contrast, with a declarative approach, the latest configuration can simply be deployed against all instances and they will be updated to match it.

#### A focus on infrastructure orchestration
Many of the long-standing tools being considered have traditionally focused on setting up and updating the configuration of existing physical or virtual machines, with support for **orchestrating** the deployment of virtual infrastructure added later as a secondary provision. We plan to use virtual machine images and docker to manage the configuration of compute resources, so orchestration of virtual infrastructure should be first class functionality in our chosen solution.

## Contributing

We welcome contributions from anyone who is interested in the project. There are lots of ways to contribute, not just writing code. See our [Contributor Guide](CONTRIBUTING.md) to learn more about how you can contribute and how we work together as a community.
