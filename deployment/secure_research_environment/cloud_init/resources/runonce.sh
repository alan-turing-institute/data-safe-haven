#! /bin/sh
for filepath in /etc/local/runonce.d/*; do
    if [ -f "$filepath" ]; then
        filename=$(basename $filepath)
        "$filepath" | tee $filename.log
        mkdir -p /etc/local/runonce.d/ran
        timestamp=$(date +%Y%m%dT%H%M%S)
        mv "$filepath" "/etc/local/runonce.d/ran/${filename}.${timestamp}"
        mv "${filename}.log" "/etc/local/runonce.d/ran/${filename}.${timestamp}.log"
    fi
done