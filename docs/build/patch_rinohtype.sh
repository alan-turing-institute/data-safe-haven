#! /bin/bash
echo "Patching rinohtype"
BASEPATH=$(python -c "import rinoh as pkg; print(pkg.__path__[0])")
echo $BASEPATH

# Generate patch
echo "Generating patch"
SCRIPT_DIR=$(realpath $(dirname "$BASH_SOURCE"))
sed -e "s|{{BASEPATH}}|$BASEPATH|g" "$SCRIPT_DIR"/rinohtype.patch > "$BASEPATH"/apply.patch

# Generate and apply patch
cd $BASEPATH
patch -p0 < apply.patch