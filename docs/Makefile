# Minimal makefile for Sphinx documentation
#

# You can set these variables from the command line, and also
# from the environment for the first two.
SPHINXOPTS    ?=
SPHINXBUILD   ?= sphinx-build
SOURCEDIR     = .
BUILDDIR      = _build
MARKDOWNSRCS  = how_to_guides/user_guides/user-guide.md \
				tutorial/deployment_tutorials/how-to-deploy-shm.md \
				tutorial/deployment_tutorials/how-to-deploy-sre.md
PDFSRCS       = $(patsubst %.md,%.pdf,$(MARKDOWNSRCS))

# Put help first so that "make" without argument is like "make help".
help:
	@$(SPHINXBUILD) -M help "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)

emojify:
	find "$(SOURCEDIR)" -name "*.md" -exec python emojify.py {} \;

.PHONY: help Makefile

%.pdf: %.md
	pretty-md-pdf -i $^ -o $@ -c markdown2pdf.json
	mkdir -p _build/html/pdf
	mv $@ _build/html/pdf

pdf: $(PDFSRCS)

# Use Sphinx for other options. $(O) is meant as a shortcut for $(SPHINXOPTS).
.DEFAULT: Makefile
	@$(SPHINXBUILD) -M $@ "$(SOURCEDIR)" "$(BUILDDIR)" $(SPHINXOPTS) $(O)
