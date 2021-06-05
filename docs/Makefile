# Minimal makefile for Sphinx documentation
#

# You can set these variables from the command line, and also
# from the environment for the first two.
SPHINXOPTS        ?=
SPHINXBUILD       ?= sphinx-build
SOURCEDIR         = .
BUILDDIR          = _build

# Determine which PDFs to build
# If you want to add a PDF make the following changes
# - Add <NAME>SOURCE and <NAME>TARGET variables
# - Add <NAME>TARGET to PDFTARGETS rule
# - Add a '<NAME>TARGET:  <NAME>SOURCE' rule
# - Edit conf.py if you want them to be downloadable
PDFTARGETDIR               = _build/html/pdf
# User guide
USERGUIDEMDSOURCE          = $(shell find . -type f -name "DSG-user-documentation.md" -o -name "safe_haven_user_guide.md" -o -name "user-guide.md")
USERGUIDEMDTARGET          = $(PDFTARGETDIR)/safe_haven_user_guide.md
# Classification flowcharts
CLASSIFICATIONFULLSOURCE   = $(shell find . -type f -name "Full-Classification-Flow-Diagram.pdf")
CLASSIFICATIONFULLTARGET   = $(PDFTARGETDIR)/data_classification_flow_full.pdf
CLASSIFICATIONSIMPLESOURCE = $(shell find . -type f -name "Simple-Classification-Flow-Diagram.pdf")
CLASSIFICATIONSIMPLETARGET = $(PDFTARGETDIR)/data_classification_flow_simple.pdf
# List of PDFs to build
PDFTARGETS                 = $(patsubst %.md,%.pdf,$(USERGUIDEMDTARGET) $(CLASSIFICATIONFULLTARGET) $(CLASSIFICATIONSIMPLETARGET))

# Put help first so that "make" without argument is like "make help".
help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

emojify:
	find "$(SOURCEDIR)" -name "*.md" -exec python emojify.py {} \;

.PHONY: help Makefile

$(USERGUIDEMDTARGET): $(USERGUIDEMDSOURCE)
	mkdir -p $(PDFTARGETDIR)
	cp $(USERGUIDEMDSOURCE) $(USERGUIDEMDTARGET)

$(CLASSIFICATIONFULLTARGET): $(CLASSIFICATIONFULLSOURCE)
	mkdir -p $(PDFTARGETDIR)
	cp $(CLASSIFICATIONFULLSOURCE) $(CLASSIFICATIONFULLTARGET)

$(CLASSIFICATIONSIMPLETARGET): $(CLASSIFICATIONSIMPLESOURCE)
	mkdir -p $(PDFTARGETDIR)
	cp $(CLASSIFICATIONSIMPLESOURCE) $(CLASSIFICATIONSIMPLETARGET)

%.pdf: %.md
	pretty-md-pdf -i $^ -o $@ -c markdown2pdf.json
	rm $^

pdf: $(PDFTARGETS)

# Use Sphinx for other options. $(O) is meant as a shortcut for $(SPHINXOPTS).
.DEFAULT: Makefile
	@$(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)
