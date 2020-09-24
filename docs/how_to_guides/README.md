## Deploying a Data Safe Haven

We provide deployment scripts and detailed deployment guides to allow you to deploy your own independent instance of our Safe Haven on your own Azure tenant. Code is in the `deployment` folder of this repository.

See the `deployment_instructions` folder.

  - [Safe Haven Management (SHM) deployment guide](deployment_instructions/how-to-deploy-shm.md) - Deploy a single Safe Haven Management (SHM) segment. This will deploy the user management and software package mirrors.


  - [Secure Research Environment (SRE) deployment guide](deployment_instructions/how-to-deploy-sre) - Deploy one Secure Research Environment (SRE) for each project you want to have its own independent, isolated analysis environment.

  - [Data Science virtual machine build instructions](deployment_instructions/how-to-customise-dsvm-image.md) - Build and publish our "batteries included" Data Science Compute virtual machine image. Customise if necessary.


## Administering a Data Safe Haven

See the `administration` folder

  - [Safe Haven Administrator guide](administration/administrator_guide.md) - Instructions for administrators of a Safe Haven. Includes how to create and add new users to a Safe Haven environment and potential solutions for some common problems users may experience.

  - [Data Classification User Guide](administration/safe_haven_data_classification_guide.md) - Step by Step instructions for Data Providers, Investigators and Referees to classify project data using our web application. This application will guide you through our [classification process](tiersflowchart.pdf) for determining the classification tier for a work package.

  - [Data Ingress guide for Data Providers](administration/provider-data-ingress.md) - Instructions for data providers, on how to transfer data into a safe haven for secure analysis.


## Using a Data Safe Haven

See the `user` folder

Once an SRE has been set up for a project within a Safe Haven, users need to know how to access it in order to carry out their research.

  - [Safe Havens User Guide](user_guides/safe_haven_user_guide.md) - Step by Step instructions on how to get set up on a Safe Haven environment. The guide has been written with Turing Data Study Groups in mind.

  - [Safe Havens Cheat Sheet](user_guides/safe-haven-user-cheat-sheet.md) - Quick instructions on how to get set up on a Safe Haven environment.

## Adding additional software Packages

See the `software-package` folder

Secure analysis environments include package mirrors.

At security Tier 3 and above, these mirrors do not include all of the packages available from the parent repository. Instead they provide access to a subset of whitelisted packages that have been vetted to mitigate the risk of introducing malicious or unsound software into the secure environment.

- [Software package whitelist policy](software-package/software-package-whitelist-policy.md) - Guidance on our software package white listing policy.

- [Software package request form](software-package/software-package-request-form.md) - Guidance on how to request a new package to be added to the environment.


## Converting documentation to PDF

There are several ways to make shareable PDF files from the documents above.
The easiest way to make shareable PDF files from the Markdown documents included here is using the `markdown2pdf.sh` script.

1. `npm` method [recommended]
- Install `npm`
- Install `pretty-markdown-pdf` with `npm install pretty-markdown-pdf` with the -g flag if you want it installed globally
- Run `./markdown2pdf.sh <file name>.md npm`

2. `LaTeX` method
- Install [`XeLaTex`](http://xetex.sourceforge.net/), generally by installing a full LaTeX environment such as [`TexLive`](http://www.tug.org/texlive/) (Windows / Linux) or [`MacTex`](http://www.tug.org/mactex/) (OSX).
- Install [`Pandoc`](https://pandoc.org/installing.html)`
- Install the `Symbola` font (https://fontlibrary.org/en/font/symbola)
- Run `./markdown2pdf.sh <file name>.md latex`
