# Safe Haven Documentation

## Learn more about the Safe Haven

  - [Policy, process and design overview](provider-overview.md) - An overview of our policies, processes and security controls for supporting productive research while maintaining the security of the data we are working with.

  - [Azure implementation overview](provider-azure-implementation-details.md) - A technical overview of the Safe Haven architecture on Azure.


## Deploying a Data Safe Haven

We provide deployment scripts and detailed deployment guides to allow you to deploy your own independent instance of our Safe Haven on your own Azure tenant. Code is in the `deployment` folder of this repository. 

1. Build and publish our "batteries included" Data Science Compute virtual machine image.

    - [Data Science virtual machine build instructions](../deployment/dsvm_images/README.md)

2. Deploy a single Safe Haven Management (SHM) segment. This will deploy the user management and software package mirrors.

    - [Safe Haven Management (SHM) deployment guide](deploy_shm_instructions.md)

3. Deploy one Secure Research Environment (SRE) for each project you want to have its own independent, isolated analysis environment.

    - [Secure Research Environment (SRE) deployment guide](deploy_sre_instructions.md)


## Administer a Data Safe Haven

  - [Create New Users](create_users.md) - Instructions for administrators to create and add new users to Data Safe Haven environments.

  - [Data Classification User Guide](safe_haven_webapp_user_guide.md) - Step by Step instructions for Data Providers, Investigators and Referees to classify project data using our web application. This application will guide you through our [classification process](tiersflowchart.pdf) for determining the classification tier for a work package.

  - [Data Ingress guide for Data Providers](provider-data-ingress.md) - Instructions for data providers, on how to transfer data into a safe haven for secure analysis.

  - [Data Egress guide for Investigators](investigator-data-egress.md) - Instructions for lead investigators, on how to transfer data out of a safe haven once you've completed with secure data research for a project.

  - [Troubleshooting user issues](troubleshooting_user_issues.md) - Some commonly encountered problems users may experience and some potential solutions.


## Using the Data Safe Haven

Once a Secure Research Environment has been set up for a project within a Safe Haven, users can get access to it to carry out secure research.

  - [Safe Havens Cheat Sheet](safe-haven-user-cheat-sheet.md) - Quick instructions on how to get set up on a Safe Haven environment.

  - [Safe Havens User Guide](safe_haven_user_guide.md) - Step by Step instructions on how to get set up on a Safe Haven environment. The guide has been written with Turing data study groups in mind. 


## Coverting documentation to PDF

There are several ways to make shareable PDF files from the documents above. You can do so either by selecting the contents of the markdown document as displayed on Github and copying and pasting into a word document and then exporting to PDF, or by using the Pandoc tool, as below:

  - Install [Pandoc](https://pandoc.org/installing.html)
  - Install [XeLaTex](http://xetex.sourceforge.net/), generally by installing a full LaTeX environment such as [Tex Live](http://www.tug.org/texlive/) (Windows / Linux) or [MacTex](http://www.tug.org/mactex/) (MacOS).
  - Create PDF using the following, replacing FILENAME with the correct file name: `pandoc FILENAME.md --pdf-engine=xelatex -o FILENAME.pdf -V geometry:margin=1.2in`
