#!/usr/bin/env bash
INFILE=$1
METHOD=${2:-npm}
FILESTEM=$(basename "$INFILE" ".md")

METHOD=$(echo $METHOD | tr [A-Z] [a-z])
if [ "$METHOD" == "npm" ]; then
    # The npm method requires:
    # - npm
    # - pretty-markdown-pdf (Install using 'npm install pretty-markdown-pdf' with the -g flag if you want it installed globally)
    pretty-md-pdf -i $FILESTEM.md -o $FILESTEM.pdf -c markdown2pdf.json

elif [ "$METHOD" == "latex" ]; then
    # The LaTeX method requires:
    # - XeLaTeX
    # - pandoc
    # - the Symbola font (https://fontlibrary.org/en/font/symbola)
    pandoc $FILESTEM.md -f gfm --pdf-engine=xelatex -o $FILESTEM.pdf -V geometry:margin=1.2in -V mainfont:Symbola

else
    echo "Method '$METHOD' was not recognised"
fi
