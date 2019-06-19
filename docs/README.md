# Safe Haven User Guide

- [Markdown version](safe_haven_user_guide.md) (always up to date)
- [PDF version](safe_haven_user_guide.pdf) (requires manual regeneration)

## Creating an updated PDF version
- Install [Pandoc](https://pandoc.org/installing.html)
- Install [XeLaTex](http://xetex.sourceforge.net/), generally by installing a full LaTeX environment such as [Tex Live](http://www.tug.org/texlive/) (Windows / Linux) or [MacTex](http://www.tug.org/mactex/) (MacOS).
- Create PDF using `pandoc safe_haven_user_guide.md --pdf-engine=xelatex -o safe_haven_user_guide.pdf -V geometry:margin=1.2in`