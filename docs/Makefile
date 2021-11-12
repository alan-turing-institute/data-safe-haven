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
# Classification flowcharts
CLASSIFICATIONFULLSOURCE   = $(shell find . -type f -name "Full-Classification-Flow-Diagram.pdf")
CLASSIFICATIONFULLTARGET   = $(PDFTARGETDIR)/data_classification_flow_full.pdf
CLASSIFICATIONSIMPLESOURCE = $(shell find . -type f -name "Simple-Classification-Flow-Diagram.pdf")
CLASSIFICATIONSIMPLETARGET = $(PDFTARGETDIR)/data_classification_flow_simple.pdf
# List of PDFs to build
PDFTARGETS                 = $(CLASSIFICATIONFULLTARGET) $(CLASSIFICATIONSIMPLETARGET)

# Put help first so that "make" without argument is like "make help".
help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(TARGETDIR)" $(SPHINXOPTS) $(O)

.PHONY: help Makefile

# Build from existing PDF
$(CLASSIFICATIONFULLTARGET): $(CLASSIFICATIONFULLSOURCE)
$(CLASSIFICATIONSIMPLETARGET): $(CLASSIFICATIONSIMPLESOURCE)

# Build rule for copying PDFs
$(CLASSIFICATIONFULLTARGET) $(CLASSIFICATIONSIMPLETARGET):
	@mkdir -p $(PDFTARGETDIR)
	@if [ "$^" ]; then cp $^ $@; echo "Copied existing PDF $^ to $@"; fi

# Build local PDF targets then call rinoh
pdf: $(PDFTARGETS)
	make rinoh

# Ensure that clean also removes the contents of $(PDFTARGETDIR)
clean:
	rm -rf $(PDFTARGETDIR)/*
	@$(SPHINXBUILD) -M clean "$(SOURCEDIR)" "$(TARGETDIR)"

# Use Sphinx for other options. $(O) is meant as a shortcut for $(SPHINXOPTS).
.DEFAULT: Makefile
	@$(SPHINXBUILD) -b $@ -c "$(CONFIGDIR)" "$(SOURCEDIR)" "$(TARGETDIR)" $(SPHINXOPTS) $(O)
