#! /bin/bash
# We need to test packages that are not pre-installed
# - by using ones which are on the tier-3 list we can test all tiers
# - by using ones which are alphabetically early and late we can test the progress of the mirror synchronisation
packages=("ahaz" "yum")

# Create local user library directory (not present by default)
Rscript -e "dir.create(path = Sys.getenv('R_LIBS_USER'), showWarnings = FALSE, recursive = TRUE)"
user_packages_dir=$(Rscript -e "Sys.getenv('R_LIBS_USER')" | cut -d ' ' -f 2 | xargs)
user_packages_dir="${user_packages_dir/#\~/$HOME}"

# Install sample packages to local user library
OUTCOME=0
for package in "${packages[@]}"; do
    echo "Attempting to install ${package}..."
    rm -rf "${user_packages_dir:?}/${package}" 2> /dev/null
    failure=0
    Rscript -e "options(warn=-1); install.packages('${package}', lib=Sys.getenv('R_LIBS_USER'), quiet=TRUE)" > /dev/null
    ls -alh "$user_packages_dir" > /dev/null 2>&1 # without this step R will not be able to find the newly-installed package
    Rscript -e "library('${package}')" || failure=1
    if [ $failure -eq 1 ]; then
        echo "... $package installation failed"
        OUTCOME=1
    else
        echo "... $package installation succeeded"
    fi
done

if [ $OUTCOME -eq 0 ]; then
    echo "CRAN working OK"
else
    echo "CRAN installation failed"
fi
