# Use "MarkupSafe" as it is in the "00/00" package directory, so should be rsync'd first
pkg1="MarkupSafe"
echo " - Attempting to install $pkg1"
pip install $pkg1  --user --quiet
status1=$?

# Use "uncertainties" as it is in the "ff/f" package directory, so should be rsync'd first
pkg2="uncertainties"
echo " - Attempting to install $pkg2"
pip install $pkg2  --user  --quiet
status2=$?

if [ $status1 -eq 0 -a $status2 -eq 0 ]; then
    echo "**PyPI working OK**"
else
    echo "**PyPI failed**"
    if [ $status1 -ne 0 ]; then
        echo " - $pkg1 installation failed"
    fi
    if [ $status2 -ne 0 ]; then
        echo " - $pkg2 installation failed"
    fi
fi


