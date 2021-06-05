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
# - Add <NAME>TARGET to PDFSRCS rule
# - Add a '<NAME>TARGET:  <NAME>SOURCE' rule
# - Edit conf.py if you want them to be downloadable
PDFTARGETDIR      = _build/html/pdf
USERGUIDEMDSOURCE = $(shell find . -type f -name "DSG-user-documentation.md" -o -name "safe_haven_user_guide.md" -o -name "user-guide.md")
USERGUIDEMDTARGET = $(PDFTARGETDIR)/safe_haven_user_guide.md
PDFSRCS           = $(patsubst %.md,%.pdf,$(USERGUIDEMDTARGET))

# Put help first so that "make" without argument is like "make help".
help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

emojify:
	find "$(SOURCEDIR)" -name "*.md" -exec python emojify.py {} \;

.PHONY: help Makefile

$(USERGUIDEMDTARGET): $(USERGUIDEMDSOURCE)
	mkdir -p $(PDFTARGETDIR)
	cp $(USERGUIDEMDSOURCE) $(USERGUIDEMDTARGET)

%.pdf: %.md
	pretty-md-pdf -i $^ -o $@ -c markdown2pdf.json
	rm $^

pdf: $(PDFSRCS)

# Use Sphinx for other options. $(O) is meant as a shortcut for $(SPHINXOPTS).
.DEFAULT: Makefile
	@$(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)
