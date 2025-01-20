#!/usr/bin/env bash
echo '{"array": ["dummy"], "variable": "dummy"}' > .mustache_config.json

while read -r yamlfile; do

    filename=$(basename -- "$yamlfile")
    filename="${filename%.*}"
    test_config=".github/resources/$filename.config.json"

    if [ -e "$test_config" ]; then
        cp "$yamlfile" expanded.tmp
        mustache "$test_config" expanded.tmp > "$yamlfile"
    else
        # replace mustache arrays
        sed "s|{{\([/#]\)[^}]*}}|{{\1array}}|g" "$yamlfile" > expanded.tmp
        # replace mustache variables
        sed -i "s|{{[^#/].\{1,\}}}|{{variable}}|g" expanded.tmp
        # perform mustache expansion overwriting original file
        mustache .mustache_config.json expanded.tmp > "$yamlfile"
    fi

done < <(find . -name "*.yml" -o -name "*.yaml")

rm expanded.tmp
