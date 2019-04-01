pip install beautifulsoup4
status1=$?

pip install wordcloud
status2=$?

if [ $status1 -eq 0 -a $status2 -eq 0 ]; then
    result="pip working OK"
else
    result="pip failed"
fi
printf "\n\n** $result **\n\n"

    

