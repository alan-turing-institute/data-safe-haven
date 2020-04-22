# Safe Haven Documentation

## Learn more about the Safe Haven

  - [Policy, process and design overview](provider-overview.md) - An overview of our policies, processes and security controls for supporting productive research while maintaining the security of the data we are working with.

  - [Azure implementation overview](provider-azure-implementation-details.md) - A technical overview of the Safe Haven architecture on Azure.


## Deploying a Data Safe Haven

We provide deployment scripts and detailed deployment guides to allow you to deploy your own independent instance of our Safe Haven on your own Azure tenant. Code is in the `deployment` folder of this repository.

1. Deploy a single Safe Haven Management (SHM) segment. This will deploy the user management and software package mirrors.

  - [Safe Haven Management (SHM) deployment guide](deploy_shm_instructions.md)

2. Build and publish our "batteries included" Data Science Compute virtual machine image.

  - [Data Science virtual machine build instructions](build_dsvm_image_instructions.md)

3. Deploy one Secure Research Environment (SRE) for each project you want to have its own independent, isolated analysis environment.

  - [Secure Research Environment (SRE) deployment guide](deploy_sre_instructions.md)


## Administer a Data Safe Haven

  - [Safe Haven Administrator guide](safe_haven_administrator_guide.md)

  - [Data Classification User Guide](safe_haven_data_classification_guide.md) - Step by Step instructions for Data Providers, Investigators and Referees to classify project data using our web application. This application will guide you through our [classification process](tiersflowchart.pdf) for determining the classification tier for a work package.

  - [Data Ingress guide for Data Providers](provider-data-ingress.md) - Instructions for data providers, on how to transfer data into a safe haven for secure analysis.

  - [Data Egress guide for Investigators](investigator-data-egress.md) - Instructions for lead investigators, on how to transfer data out of a safe haven once you've completed with secure data research for a project.


## Using the Data Safe Haven

Once a Secure Research Environment has been set up for a project within a Safe Haven, users can get access to it to carry out secure research.

  - [Safe Havens Cheat Sheet](safe-haven-user-cheat-sheet.md) - Quick instructions on how to get set up on a Safe Haven environment.

  - [Safe Havens User Guide](safe_haven_user_guide.md) - Step by Step instructions on how to get set up on a Safe Haven environment. The guide has been written with Turing data study groups in mind.


## Converting documentation to PDF

There are several ways to make shareable PDF files from the documents above.
The easiest way to make shareable PDF files from the Markdown documents included here is using the `markdown2pdf.sh` script.

1. `npm` method [recommended]
- Install `npm`
- Install `pretty-markdown-pdf` with `npm install pretty-markdown-pdf`
- Run `./markdown2pdf.sh <file name>.md npm`

2. `LaTeX` method
- Install [`XeLaTex`](http://xetex.sourceforge.net/), generally by installing a full LaTeX environment such as [`TexLive`](http://www.tug.org/texlive/) (Windows / Linux) or [`MacTex`](http://www.tug.org/mactex/) (OSX).
- Install [`Pandoc`](https://pandoc.org/installing.html)`
- Install the `Symbola` font (https://fontlibrary.org/en/font/symbola)
- Run `./markdown2pdf.sh <file name>.md latex`
