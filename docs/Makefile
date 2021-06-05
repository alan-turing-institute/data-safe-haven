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
# User guide
PKGREQUESTMDSOURCE         = $(shell find . -type f -name "software-package-request-form.md")
PKGREQUESTMDTARGET         = $(PDFTARGETDIR)/safe_haven_software_request_form.md
# Classification flowcharts
CLASSIFICATIONFULLSOURCE   = $(shell find . -type f -name "Full-Classification-Flow-Diagram.pdf")
CLASSIFICATIONFULLTARGET   = $(PDFTARGETDIR)/data_classification_flow_full.pdf
CLASSIFICATIONSIMPLESOURCE = $(shell find . -type f -name "Simple-Classification-Flow-Diagram.pdf")
CLASSIFICATIONSIMPLETARGET = $(PDFTARGETDIR)/data_classification_flow_simple.pdf
# List of PDFs to build
PDFTARGETS                 = $(patsubst %.md,%.pdf,$(USERGUIDEMDTARGET) $(PKGREQUESTMDTARGET) $(CLASSIFICATIONFULLTARGET) $(CLASSIFICATIONSIMPLETARGET))

# Put help first so that "make" without argument is like "make help".
help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

.PHONY: help Makefile

$(USERGUIDEMDTARGET): $(USERGUIDEMDSOURCE)
	mkdir -p $(PDFTARGETDIR)
	cp $(USERGUIDEMDSOURCE) $(USERGUIDEMDTARGET)

$(PKGREQUESTMDTARGET): $(PKGREQUESTMDSOURCE)
	mkdir -p $(PDFTARGETDIR)
	cp $(PKGREQUESTMDSOURCE) $(PKGREQUESTMDTARGET)

$(CLASSIFICATIONFULLTARGET): $(CLASSIFICATIONFULLSOURCE)
	mkdir -p $(PDFTARGETDIR)
	cp $(CLASSIFICATIONFULLSOURCE) $(CLASSIFICATIONFULLTARGET)

$(CLASSIFICATIONSIMPLETARGET): $(CLASSIFICATIONSIMPLESOURCE)
	mkdir -p $(PDFTARGETDIR)
	cp $(CLASSIFICATIONSIMPLESOURCE) $(CLASSIFICATIONSIMPLETARGET)

# Build single PDF using pretty-md-pdf
%.pdf: %.md
	pretty-md-pdf -i $^ -o $@ -c markdown2pdf.json
	rm $^

# Convert emoji codes to Unicode in all Markdown files
emojify:
	find "$(SOURCEDIR)" -name "*.md" -exec python emojify.py {} \;

# Build all PDF targets
pdf: $(PDFTARGETS)

# Ensure that clean also removes the contents of $(PDFTARGETDIR)
clean:
	rm -rf $(PDFTARGETDIR)/*
	@$(SPHINXBUILD) -M clean "$(SOURCEDIR)" "$(BUILDDIR)"

# Use Sphinx for other options. $(O) is meant as a shortcut for $(SPHINXOPTS).
.DEFAULT: Makefile
	@$(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)
