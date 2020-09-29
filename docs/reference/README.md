# Reference guides

Our reference material for how to implement some technical aspect of our Safe Haven.

We currently only have an azure implementation of our Safe Havens, thus a lot of reference material can be found on the [Microsoft azure website](https://azure.microsoft.com/en-gb/) or the [Azure web portal](https://azure.microsoft.com/en-gb/features/azure-portal/).

These reference guides assume some knowledge of how our Safe Havens work.




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
