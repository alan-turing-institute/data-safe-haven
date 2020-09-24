## Learn more about the Safe Haven

See the `overview` folder

  - [Policy, process and design overview](overview/provider-overview.md) - An overview of our policies, processes and security controls for supporting productive research while maintaining the security of the data we are working with.

  - [Azure implementation overview](overview/provider-azure-implementation-details.md) - A technical overview of the Safe Haven architecture on Azure.

## Classification


## Safe Haven design decisions

See the `design_decisions` folder

We outline a number of our design decisions when building our Safe Havens. This includes reasoning for our different choices but also highlights potential limitations for our Safe Havens and how this may affect things like cyber security.

- [Safe Haven resilience](design_decisions/physical_resilence_and_availability.md) - Documentation on the physical resilience of the Safe Haven and our design decisions involved.

- [Sensitive data handling](design_decisions/best-practice-sensitive-data-handling.md) - Guidance on our approach to handling sensitive research data and our related design decisions.

- [Simple Classification diagram](design_decisions/Simple Classification Flow Diagram.pdf) - High level diagram detailing our classification process

- [Full Classification diagram](design_decisions/Full Classification Flow Diagram.pdf) - Detailed, full diagram detailing our classification process

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
