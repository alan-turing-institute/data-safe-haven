# Tutorials

Our tutorials provide a very hands on guide to implementing some aspect of the Safe Haven.

They require no prior knowledge and are a good place to start.

## User Tutorials

See the `user-tutorials` folder

  - [Safe Havens Cheat Sheet](user_tutorials/safe-haven-user-cheat-sheet.md) - Quick instructions on how to get set up on a Safe Haven environment.




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
