# Take packages which are alphabetically first and last on our whitelist
packages=("abind" "zoo")

# Create local user library directory (not present by default)
Rscript -e "dir.create(path = Sys.getenv('R_LIBS_USER'), showWarnings = FALSE, recursive = TRUE)"

# Install sample packages to local user library
OUTCOME=0
for package in ${packages[@]}; do
    echo "Attempting to install $package"
    failure=0
    Rscript -e "options(warn=2); install.packages('${package}', lib=Sys.getenv('R_LIBS_USER'), quiet=TRUE)" || failure=1
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