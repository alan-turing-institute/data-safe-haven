# Data Safe Haven
Welcome to the Data Safe Havens project. This repository contains the code necessary to deploy an instance of the Alan Turing Institute's Data Safe Haven, and instructions on how to use it.

## What is a Data Safe Haven

Secure environments for analysis of sensitive datasets are essential for research. Data Safe Havens provide a way to build a secure environment for data analysis.

[Overview](provider-overview.md) - Find out more about Data Safe Havens, and how to use our model.
[Implementation on Azure](provider-azure-implementation-details.md) - A technical overview of the Safe Haven architecture on Azure.
[Data Ingress](provider-data-ingress.md) - Instructions for data providers, on how to transfer data into a safe haven for secure analysis.

## Setting up a Data Safe Haven

You can set up a data safe haven yourself.

[Safe Haven Management](shm_build_instructions.md) - Instructions on how to build a Safe Haven Management environment in Azure.
[Secure Research Environment](dsg_build_instructions.md) - Instructions on how to build a Secure Research Environment in Azure.
[Create New Users](https://github.com/alan-turing-institute/data-safe-haven/blob/9213c9b949be04a2a8ea5c075ee698f23115ef9f/new_dsg_environment/create-users/README.md) - Create and add new users to Data Safe Haven environments.

Before you go ahead to set up a Data Safe Haven, you'll need to have the following pre-requisites:
- `Powershell`
    - needed to deploy infrastructure
- `bash`
    - needed to deploy infrastructure
- `Microsoft Azure` account
    - target for infrastructure deployment

[Design choices](https://github.com/alan-turing-institute/data-safe-haven/tree/9213c9b949be04a2a8ea5c075ee698f23115ef9f/design) - You can find out more about the design of Data Safe Havens here.

## Using a Data Safe Havens

Once a Safe Haven environment has been set up for a project, you can get access to it to carry out secure research.

[Data Classification User Guide](safe_haven_webapp_user_guide.md) - Step by Step instructions on classify project data using our classification WebApp.
[Safe Haven Cheat Sheet](safe-haven-user-cheat-sheet.md) - Quick instructions on how to get set up on a Safe Haven environment.
[Safe Haven User Guide](safe_haven_user_guide.md) - Step by Step instructions on how to get set up on a Safe Haven environment.

## Contributing
We welcome contributions from anyone who is interested in the project. Therte are lots of ways to contribute, not just writing code. See our [Contributor Guide](https://github.com/alan-turing-institute/data-safe-haven/blob/master/CONTRIBUTING.md) to learn more about how you can contribute and how we work together as a community.
