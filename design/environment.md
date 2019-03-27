# Analysis environment: design

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

---

### Sign off

If you have read this document and you're happy with its contents, please add your name and the date on which you read the wiki page (as it may be updated after you've read it!)

| Name | Date | Comments |
| ---- | ---- | -------- |
| Catalina Vallejos | 17 September 2018 | R version is missing. I added link to standard R library. We might consider [rstan](https://cran.r-project.org/web/packages/rstan/index.html) installed as [installation from CRAN](https://github.com/stan-dev/rstan/wiki/Installing-RStan-on-Mac-or-Linux) is not always trivial |
| Catalina Vallejos | 20 November 2018 | Added link to top downloaded Bioconductor packages (version 3.8). List includes top 200 packages, stratified in groups of 50. Also included additional list of packages that I curated for a different DSH environment (focusing on those that were not included in Sebastian's list)
| James Robinson | 21 November 2018 | Consolidated various lists of R packages into one list linked from here
