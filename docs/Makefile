# Minimal makefile for Sphinx documentation
#

# You can set these variables from the command line, and also
# from the environment for the first two.
SPHINXOPTS        ?=
SPHINXBUILD       ?= sphinx-build
SOURCEDIR         = .
CONFIGDIR         = build
TARGETDIR         = _output

# Determine which PDFs to build
# If you want to add a PDF make the following changes
# - Add <NAME>SOURCE and <NAME>TARGET variables
# - Add <NAME>TARGET to PDFTARGETS rule
# - Add a '<NAME>TARGET:  <NAME>SOURCE' rule
# - Edit conf.py if you want them to be downloadable
PDFTARGETDIR               = $(TARGETDIR)/pdf

# Put help first so that "make" without argument is like "make help".
help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(TARGETDIR)" $(SPHINXOPTS) $(O)

.PHONY: help Makefile

# 'all' will make HTML and PDFs
all: html pdf

# Use rinoh (via Sphinx) to build PDFs from Markdown
pdf:
	make rinoh
	rm $(PDFTARGETDIR)/*.rtc
	rm $(PDFTARGETDIR)/*.stylelog

# Ensure that clean also removes the contents of $(PDFTARGETDIR)
clean:
	rm -rf $(PDFTARGETDIR)/*
	@$(SPHINXBUILD) -M clean "$(SOURCEDIR)" "$(TARGETDIR)"

# Use Sphinx for other options. $(O) is meant as a shortcut for $(SPHINXOPTS).
.DEFAULT: Makefile
	@$(SPHINXBUILD) -b $@ -c "$(CONFIGDIR)" "$(SOURCEDIR)" "$(TARGETDIR)" $(SPHINXOPTS) $(O)
