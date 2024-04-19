#! /bin/sh
set -e

# Check for required arguments
if [ "$#" -ne 2 ]; then
    echo "Usage: update_python_dependencies [environment_name] [target]"
    exit 1
fi
ENV_NAME=$1
TARGET=$2

# Check for pip-compile
if ! command -v pip-compile > /dev/null; then
    echo "pip-compile could not be found"
    exit 1
fi

# Run pip-compile
if [ "$ENV_NAME" = "default" ]; then
    pip-compile -U pyproject.toml -o "$TARGET"
else
    hatch env show --json | jq -r ".${ENV_NAME}.dependencies | .[]" | pip-compile -U - -o "$TARGET"
fi
