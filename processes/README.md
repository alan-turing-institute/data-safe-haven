# Process and system documentation

## Documents for external stakeholders
- [Safe Haven overview](./provider-overview.md)
- [Azure implementation overview](./provider-azure-implementation-details.md)

## Creating self-contained PDFs
- Install [Pandoc](https://pandoc.org/installing.html)
- Install [XeLaTex](http://xetex.sourceforge.net/), generally by installing a full LaTeX environment such as [Tex Live](http://www.tug.org/texlive/) (Windows / Linux) or [MacTex](http://www.tug.org/mactex/) (MacOS).
- Create PDF using `./markdown2pdf.sh <markdown-filename>.md`