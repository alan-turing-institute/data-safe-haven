# Create local user library directory (not present by default)
Rscript -e "dir.create(path = Sys.getenv('R_LIBS_USER'), showWarnings = FALSE, recursive = TRUE)"

# install sample packages to local user library
pkg1="A3"
echo " - Attempting to install $pkg1"
Rscript -e "install.packages('${pkg1}', lib = Sys.getenv('R_LIBS_USER'), quiet=TRUE)"
status1=$?

pkg2="zyp"
echo " - Attempting to install $pkg2"
Rscript -e "install.packages('${pkg2}', lib = Sys.getenv('R_LIBS_USER'), quiet=TRUE)"
status2=$?

if [ $status1 -eq 0 -a $status2 -eq 0 ]; then
    echo "**CRAN working OK**"
else
    echo "**CRAN failed**"
    if [ $status1 -ne 0 ]; then
        echo " - $pkg1 installation failed"
    fi
    if [ $status2 -ne 0 ]; then
        echo " - $pkg2 installation failed"
    fi
fi
