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
while getopts "bd:hl" option; do
    case $option in
        b)
            operation="backup"
            ;;
        d)
            backup_directory=$OPTARG
            ;;
        h)
            usage
            ;;
        l)
            operation="load"
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
        mkdir -p docs/build
        rm -rf docs/build/*
        cp -v -R "$backup_directory"/build/* docs/build
        cp -v "$backup_directory"/Makefile docs/
        # Use the first of these files that exists as the index:
        # - index.md
        # - README.md
        # - DSG-user-documentation.md
        # - An empty index.md
        if [ -e "docs/index.md" ]; then
            true
        elif [ -e "docs/README.md" ]; then
            mv docs/README.md docs/index.md
        elif [ -e "docs/DSG-user-documentation.md" ]; then
            mv docs/DSG-user-documentation.md docs/index.md
        else
            cp "${backup_directory}/build/meta/index.empty.md" docs/index.md
        fi
        ;;
esac
