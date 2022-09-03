#! /bin/bash

# Document usage for this script
usage() {
    echo "usage: $0 [-h] -d directory -n name -p"
    echo "  -h                              display help"
    echo "  -d directory [required]         specify directory for docs to be checked"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
docs_directory=""
while getopts "d:h" option; do
    case $option in
    d)
        docs_directory=$OPTARG
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        ;;
    esac
done
if [[ -z "$docs_directory" ]]; then usage; fi

# Run HTML proofer on docs output
# - allow links to "#"
# - rewrite the base URL
# - ignore links to:
#   - the data-safe-haven repo (as it is private)
#   - the data-classification-app repo (as it is private)
#   - turing.ac.uk (as it requires a CAPTCHA)
export LC_CTYPE="en_GB.UTF-8"
export LC_ALL="en_GB.UTF-8"
htmlproofer $docs_directory \
--allow-hash-href \
--check-favicon \
--check-html \
--check-img-http \
--enforce-https \
--file-ignore "*/_static/" \
--http-status-ignore "403,429,503" \
--url-swap "^\/data-safe-haven:/.." \
--url-ignore "/github.com\/alan-turing-institute\/data-safe-haven/,/github.com\/alan-turing-institute\/data-classification-app/,/turing.ac.uk\//"