#! /bin/bash

# Get paths
SCRIPT_DIR=$(realpath "$(dirname "$BASH_SOURCE")")
BASEPATH=$(python -c "import rinoh as pkg; print(pkg.__path__[0])")
echo "Preparing to patch rinohtype at ${BASEPATH}"
cd "$BASEPATH" || (echo "Could not find path!"; exit 1)

# Apply patch from rinohtype directory
PATCH_PATH=$(ls "$SCRIPT_DIR/rinohtype.patch" 2> /dev/null)
if [ ! "$PATCH_PATH" ]; then
    echo "Could not find patch!"
    exit 1
fi
echo "Applying patch from ${PATCH_PATH}"
patch -p0 < "$PATCH_PATH"