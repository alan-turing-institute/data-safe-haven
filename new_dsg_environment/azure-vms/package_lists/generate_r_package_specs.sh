#!/usr/bin/env bash

# Insert block header
echo "  # ***** START DEFINING PACKAGES FOR R ***"
echo "  # DO NOT EDIT BY HAND: Update cran.list and bioconductor.list then run generate_r_package_specs.sh to re-generate this section"

# Construct formatted lists

CRANPACKAGES=$(cat cran.list | sed -e "s/^/'/" -e "s/$/',/" | tr "\n" " " | sed -e "s/', $/'/")
echo "  - export CRANPACKAGES=\"$CRANPACKAGES\""
BIOCPACKAGES=$(cat bioconductor.list | sed -e "s/^/'/" -e "s/$/',/" | tr "\n" " " | sed -e "s/', $/'/")
echo "  - export BIOCPACKAGES=\"$BIOCPACKAGES\""

# Insert block footer
echo "  # ***** END DEFINING PACKAGES FOR R ***"
