#! /bin/bash

# Document usage for this script
usage() {
    echo "usage: $0 [-h] -d directory -n name -p"
    echo "  -h                              display help"
    echo "  -d directory [required]         specify directory for docs to be checked"
    echo "  -b base_url [required]          base url for site"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
docs_directory=""
while getopts "d:b:h" option; do
    case $option in
    d)
        docs_directory=$OPTARG
        ;;
    b)
        base_url=$OPTARG
        ;;
    h)
        usage
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
--enforce-https \
--ignore_files "*/_static/" \
--root-dir "$(readlink -f ${docs_directory})"
--swap_urls "^\/${base_url}:/.." \
--url-ignore "/github.com\/alan-turing-institute\/data-safe-haven/,/github.com\/alan-turing-institute\/data-classification-app/,/turing.ac.uk\//"