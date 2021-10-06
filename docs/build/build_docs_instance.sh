#! /bin/bash

# Document usage for this script
usage() {
    echo "usage: $0 [-h] -d directory -n name"
    echo "  -h                              display help"
    echo "  -d directory [required]         specify directory where backups are stored"
    echo "  -n name [required]              name of the version being built"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
name=""
output_directory=""
while getopts "d:hn:" option; do
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
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done
if [[ -z "$name" ]] || [[ -z "$output_directory" ]]; then usage; fi


# Build the HTML docs
make -C docs clean
make -C docs emojify
make -C docs html pdf

# Store docs in the output directory
echo "Moving output to ${output_directory}/${name}"
mv docs/_output "${output_directory}/${name}"
ls -alh "${output_directory}/${name}"

# Reset local changes
git reset --hard HEAD
git clean -fd
