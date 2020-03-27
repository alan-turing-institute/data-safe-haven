#!/usr/bin/env bash
INFILE=$1
FILESTEM=$(basename "$INFILE" ".md")

pandoc $FILESTEM.md --pdf-engine=xelatex -o $FILESTEM.pdf -V geometry:margin=1.2in