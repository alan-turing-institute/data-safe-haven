# Use "MarkupSafe" as it is the first linux package on the Tier-3 whitelist (in the "00/00" package directory) so should be rsync'd near the end
# Use "Fiona" as it is the last linux package on the Tier-3 whitelist (in the "ff/fb" package directory) so should be rsync'd near the end
# Also take packages which are alphabetically early and late in the Tier-3 list
packages=("MarkupSafe" "Fiona" "aequitas" "zipp")

# Create local user library directory (not present by default)
Rscript -e "dir.create(path = Sys.getenv('R_LIBS_USER'), showWarnings = FALSE, recursive = TRUE)"

# Install sample packages to local user library
OUTCOME=0
for package in ${packages[@]}; do
    echo "Attempting to install $package"
    failure=0
    pip install $package --user --quiet || failure=1
    if [ $failure -eq 1 ]; then
        echo "... $package installation failed"
        OUTCOME=1
    else
        echo "... $package installation succeeded"
    fi
done

if [ $OUTCOME -eq 0 ]; then
    echo "PyPI working OK"
else
    echo "PyPI installation failed"
fi


