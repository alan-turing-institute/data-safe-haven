pkg1="a2svm"
pip install $pkg1
status1=$?

pkg2="z80"
pip install $pkg2
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
    

