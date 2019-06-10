# Process and system documentation

## Contents
- [Safe Haven overview](./provider-overview.md)
- [Azure implementation overview](./provider-azure-implementation-details.md)

## Creating PDFs for sharing outside of this repo
- Install [Pandoc](https://pandoc.org/installing.html)
- Install [XeLaTex](http://xetex.sourceforge.net/), generally by installing a full LaTeX environment such as [Tex Live](http://www.tug.org/texlive/) (Windows / Linux) or [MacTex](http://www.tug.org/mactex/) (MacOS).
- Create PDF using `./markdown2pdf.sh <markdown-filename>.md`