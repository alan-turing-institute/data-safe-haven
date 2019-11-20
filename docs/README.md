# Safe Haven User Guides

- [Safe Haven Full Guide](safe_haven_user_guide.md) - This document gives step by step instructions for how to get set up on a Safe Haven tool. The guide has been written with Turing data study groups in mind. 

- [Safe Haven Cheat Sheet](safe-haven-user-cheat-sheet.md) - An abbreviated user guide for the safe haven tool.

- [Safe Haven WebApp](safe_haven_webapp_user_guide.md) A user guide for the Safe Haven web application - a tool you can use to classify data to a particular tier, before putting it in a Safe Haven environment.

## Sharing the user guides

There are several ways to make shareable PDF files from the documents above. You can do so either by copying to a word document and exporting to PDF, or using the Pandoc tool, as below:
- Install [Pandoc](https://pandoc.org/installing.html)
- Install [XeLaTex](http://xetex.sourceforge.net/), generally by installing a full LaTeX environment such as [Tex Live](http://www.tug.org/texlive/) (Windows / Linux) or [MacTex](http://www.tug.org/mactex/) (MacOS).
- Create PDF using the following, replacing FILENAME with the correct file name: `pandoc FILENAME.md --pdf-engine=xelatex -o FILENAME.pdf -V geometry:margin=1.2in`
