#! /bin/sh

# Document usage for this script
usage() {
    echo "usage: $(basename "$0") -d directory [-h] [-p port]"
    echo "  -d directory [required]         specify directory where output should be stored"
    echo "  -h                              display help"
    echo "  -p port                         specify port to run webserver on [default: 8080]"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
target_directory=""
port="8080"
while getopts "d:hp:" option; do
    case $option in
    d)
        target_directory=$OPTARG
        ;;
    h)
        usage
        ;;
    p)
        port=$OPTARG
        ;;
    \?)
        echo "Invalid option: -$OPTARG" >&2
        ;;
    esac
done

# Check that target and output directories exist
target_directory="$(realpath "$target_directory")"
if [ -z "$target_directory" ]; then usage; fi
output_directory="${target_directory:?}/data-safe-haven"
mkdir -p "${output_directory}"

# Check that output directory is empty
if [ "$(ls -A "$output_directory")" ]; then
    while true; do
        echo "$output_directory is not empty. Delete its contents? [y/n] "
        read -r response
        case $response in
        [Yy]*)
            rm -rf "${output_directory}"
            break
            ;;
        [Nn]*) exit 0 ;;
        *) echo "Please answer yes or no." ;;
        esac
    done
fi

# Build docs with act
echo "Building docs"
act -j build_docs -C "$(git rev-parse --show-toplevel)" 2>/dev/null

# Move the docs to a local directory
echo "Moving docs to target directory"
CONTAINER_ID=$(docker container ls -a | grep build-docs | cut -d ' ' -f 1)
echo "Starting container $(docker container start "$CONTAINER_ID")..."
DOCS_DIR=$(dirname "$(docker exec -it "$CONTAINER_ID" /bin/bash -c "find /tmp -type d -name develop")")
docker cp "${CONTAINER_ID}:${DOCS_DIR}/." "${output_directory}"
echo "Stopping container $(docker container stop "$CONTAINER_ID")"

# Start a Python webserver in local directory
echo "Starting webserver at http://localhost:${port}"
python -m http.server --directory "${target_directory}" "$port"
