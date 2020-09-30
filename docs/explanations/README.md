## Learn more about the Safe Haven


We provide a high level overview of the Data Safe Haven project.


  - [Policy, process and design overview](overview/provider-overview.md) - An overview of our policies, processes and security controls for supporting productive research while maintaining the security of the data we are working with.

  - [Azure implementation overview](overview/provider-azure-implementation-details.md) - A technical overview of the Safe Haven architecture on Azure.

## Classification

We visually present our classification process for determining the security tier for a data work package.

- [Classification overview](classification/classification-overview.md) - A full overview of the classification process, including the related technical and policy decisions.


## Security

We detail various design decisions that impact the security of our Safe Haven implementation. This includes reasoning for our different choices but also highlights potential limitations for our Safe Havens and how this may affect things like cyber security.
See the `security_decisions` folder

- [Safe Haven resilience](security_decisions/physical_resilence_and_availability.md) - Documentation on the physical resilience of the Safe Haven and our design decisions involved.

## Ingress and Egress data

We detail our processes for ingressing and egressing data.

  - [Data Egress guide for Investigators](ingress_and_egress/investigator-data-egress.md) - Instructions for lead investigators, on how to transfer data out of a safe haven once you've completed with secure data research for a project.



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
