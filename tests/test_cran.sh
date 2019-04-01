Rscript -e "install.packages('cluster', lib = '~/R/x86_64-pc-linux-gnu-library/3.5')"
status1=$?

Rscript -e "install.packages('yaml', lib = '~/R/x86_64-pc-linux-gnu-library/3.5')"
status2=$?

if [ $status1 -eq 0 -a $status2 -eq 0 ]; then
    result="CRAN working OK"
else
    result="CRAN failed"
fi
printf "\n\n** $result **\n\n"
