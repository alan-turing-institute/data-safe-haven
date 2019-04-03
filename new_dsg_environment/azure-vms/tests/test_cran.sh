# Create local user library directory (not present by default)
Rscript -e "dir.create(path = Sys.getenv('R_LIBS_USER'), showWarnings = FALSE, recursive = TRUE)"

# install sample packages to local user library
pkg1="A3"
Rscript -e "install.packages('${pkg1}', lib = Sys.getenv('R_LIBS_USER'))"
status1=$?

pkg2="zyp"
Rscript -e "install.packages('${pkg1}', lib = Sys.getenv('R_LIBS_USER'))"
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
