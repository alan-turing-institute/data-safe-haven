# Tutorials and overview

**Recommended if**: you have no prior experience using our Safe Havens and want to be guided through the basics.

This documentation requires no prior knowledge and is a good place to start.

## Quick overview

Our overview documentation provides a quick summary of the Safe Haven project.

+ [What is a Safe Haven](quick_overview/what-is-a-safe-haven.md) PLACEHOLDER.
+ [Why might you want to use a Safe Haven](quick_overview/why-might-you-use-a-safe-haven.md) PLACEHOLDER.
+ [Is this Safe Haven suitable for you?](quick_overview/is-this-safe-haven-suitable-for-you.md) PLACEHOLDER.

## Deployment tutorials

Step by step tutorials on how to deploy a Safe Haven.

We provide deployment scripts and detailed deployment guides to allow you to deploy your own independent instance of our Safe Haven on your own Azure tenant. Code is in the `deployment` folder of this repository.

+ [Safe Haven Management (SHM) deployment guide](deployment_instructions/how-to-deploy-shm.md)
  + Deploy a single Safe Haven Management (SHM) segment. This will deploy the user management and software package mirrors.
+ [Data Science virtual machine build instructions](deployment_instructions/how-to-customise-dsvm-image.md)
  + Build and publish our "batteries included" Data Science Compute virtual machine image. Customise if necessary.
+ [Secure Research Environment (SRE) deployment guide](deployment_instructions/how-to-deploy-sre)
  + Deploy one Secure Research Environment (SRE) for each project you want to have its own independent, isolated analysis environment.
