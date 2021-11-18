#! /bin/bash

# Document usage for this script
usage() {
    echo "usage: $0 [-h] -d directory -n name -p"
    echo "  -h                              display help"
    echo "  -d directory [required]         specify directory where backups are stored"
    echo "  -n name [required]              name of the version being built"
    echo "  -p                              also build PDF versions"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
name=""
output_directory=""
while getopts "d:hn:p" option; do
    case $option in
    d)
        output_directory=$OPTARG
        ;;
    h)
        usage
        ;;
    n)
        name=$OPTARG
        ;;
    p)
        make_pdf=1
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        ;;
    esac
done
if [[ -z "$name" ]] || [[ -z "$output_directory" ]]; then usage; fi

# In pre-Sphinx releases, some files contain invalid Markdown
# We remove trailing '\' characters from all Markdown files
# We remove an incorrectly formatted table in 'software-package-request-form.md'
echo "Fixing invalid Markdown..."
find . -name "*.md" -exec sed -i "s|\\\\$||g" {} +
SOFTWARE_PACKAGE_REQUEST_FORM_PATH=$(find . -name 'software-package-request-form.md')
if [ -n "$SOFTWARE_PACKAGE_REQUEST_FORM_PATH" ]; then
    sed -i "/[ -]|[ -]/d" "$(find . -name 'software-package-request-form.md')"
fi
# Output the fixes that have been made
git diff "**/*.md" ':(exclude)docs/README.md'

# Build the docs
make -C docs clean
if [ "$make_pdf" = "1" ]; then
    make -C docs html pdf
else
    make -C docs html
fi

# Store docs in the output directory
echo "Moving output to ${output_directory}/${name}"
mv docs/_output "${output_directory}/${name}"

# Reset local changes
git reset --hard HEAD
git clean -fd
