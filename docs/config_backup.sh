#! /bin/bash

# Document usage for this script
usage() {
    echo "usage: $0 [-h] -d directory -b|-l"
    echo "  -h                              display help"
    echo "  -d directory [required]         specify directory where backups are stored"
    echo "  -b backup [this or -l required] backup to directory"
    echo "  -l load [this or -b required]   load from directory"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
operation=""
backup_directory=""
while getopts "hbld:" option; do
    case $option in
        h)
            usage
            ;;
        b)
            operation="backup"
            ;;
        l)
            operation="load"
            ;;
        d)
            backup_directory=$OPTARG
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done
if [[ -z "$operation" ]] || [[ -z "$backup_directory" ]]; then usage; fi


case $operation in
    # Backup files to directory
    backup)
        echo "Backing up files to $backup_directory"
        mkdir -p "$backup_directory"
        cp -R docs/* "$backup_directory"
        ;;
    # Load files from directory
    load)
        if [ ! -d "$backup_directory" ]; then
            echo "'$backup_directory' does not exist!"
            exit 1
        fi
        echo "Loading files from $backup_directory"
        # Copy Sphinx configuration files
        mkdir -p docs/_templates docs/_static
        cp -v "$backup_directory"/conf.py docs/
        cp -v "$backup_directory"/Makefile docs/
        cp -v "$backup_directory"/_templates/* docs/_templates
        cp -v "$backup_directory"/_static/* docs/_static
        # Use README.md if there is one, otherwise the default index
        if [ ! -e "docs/index.md" ]; then
            if [ -e "docs/README.md" ]; then
                mv docs/README.md docs/index.md
            else
                cp "$backup_directory"/meta/default.template docs/index.md
            fi
        fi
        ;;
esac