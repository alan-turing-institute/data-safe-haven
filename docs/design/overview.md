# Design principles
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


# Design of the analysis environment
The analysis environment is a Linux-based virtual machine, pre-configured with typical software necessary for data science work. Other tools can be installed following the [Software ingress policy](https://github.com/alan-turing-institute/data-safe-haven/wiki/SoftwareIngressPolicy).

Note that we have chosen to *not* support analyses on other operating systems (Windows or Mac for example). There are very few data science analyses that can not be conducted on Linux and very few data science researchers who would not be able to perform their work via a Linux OS. The incremental gain that could come from supporting additional operating systems would not balance out the additional support requirements.

The section below details the default software installed within the analysis environment.

## Default software in analysis environment

### Programming languages
- Python (2.7, 3.5 and 3.6)
  - Anaconda env: `py27`
    - includes all packages from [here](https://docs.anaconda.com/anaconda/packages/py2.7_linux-64/), including `pip`
    - in addition the following packages are installed: `ipykernel`, `jupyter_client`, `jupyterlab`, `keras`, `notebook`, `pystan`, `pytorch`, `r-irkernel`, `tensorflow`, `torchvision`
  - Anaconda env: `py35`
    - includes all packages from [here](https://docs.anaconda.com/anaconda/packages/py3.5_linux-64/), including `pip`
    - in addition the following packages are installed: `ipykernel`, `jupyterhub`, `jupyter_client`, `jupyterlab`, `keras`, `notebook`, `pystan`, `pytorch`, `r-irkernel`, `tensorflow`, `torchvision`
  - Anaconda env: `py36`
    - includes all packages from [here](https://docs.anaconda.com/anaconda/packages/py3.6_linux-64/), including `pip`
    - in addition the following packages are installed: `ipykernel`, `jupyterhub`, `jupyter_client`, `jupyterlab`, `keras`, `notebook`, `pystan`, `pytorch`, `r-irkernel`, `tensorflow`, `torchvision`
   - Note that additional packages can be installed by the user from the internal mirror of the conda and pip package repositories and internet access will not be required for these installations.
- R (CRAN/Bioconductor)
  - A large number of R packages will be included in the VM. The list is [here](https://github.com/alan-turing-institute/data-safe-haven/wiki/R-package-list). If any necessary package is missing, please make a note so that the list (and the VM) can be updated appropriately.
- PostgreSQL
- Julia 1.0 (or is a different version preferred - clarification needed here)
- Java JVM
- .NET Core and mono
- C/C++
- Fortran


### Development tools
- Bash terminal with basic command line utilities
- Git
- htop
- Web browser
- Text editors
  - vim
  - emacs
  - nano
  - VS Code
  - Atom
    - Note that VS Code and Atom require various extensions to be added while internet access is available. The process for this should follow the [Software ingress policy](https://github.com/alan-turing-institute/data-safe-haven/wiki/SoftwareIngressPolicy).
- RStudio desktop and server
- Jupyter Notebook server with R, Python and Julia kernels
- JupyterLab/JupyterHub
- Docker (possible issues with root access?)
- Virtualization software for code requiring root privileges (solving the Docker issue above?)


### Management tools
- Azure CLI and other necessary tools (azcopy)
- Azure Storage Explorer

### Machine learning tools
- Stan
- Spark
- Tensorflow
- Torch, PyTorch
- Keras
- CUDA
- OpenCV

### Visualisation tools
- FFMPEG
- Paraview

## Default software on secure developer devices

There are two types of secure devices with different default behaviour:

1. **Short term loan device**

     Device on a short term loan does not need any installed software beyond tools necessary to connect to the safe haven environment. All of the analysis work should be done within the secure environment.

2. **Device with long term usage**

    The user should get a window of opportunity to install any required software themselves, with internet access. If the device is Linux-based (or Mac if compatible), it may be pre-installed with the default software. As a default policy, only Linux environments should be pre-configured.

For additional information see the [Device tiers](https://github.com/alan-turing-institute/data-safe-haven/wiki/DeviceTiers).

## Adding software to the list of defaults

The process of adding software to the tools installed by default is detailed in the [Software ingress process](SoftwareIngressProcess) document.

