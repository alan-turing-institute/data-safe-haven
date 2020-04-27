#! /bin/bash

# Require three arguments: environment name; (quoted) list of conda packages; (quoted) list of pip packages
if [ $# -ne 3 ]; then
    exit 1
fi
ENV_NAME=$1
CONDA_PACKAGES=$2
PIP_PACKAGES=$3

# Set version
VERSION=$(echo $ENV_NAME | sed "s/py\([0-9]\)\([0-9]\)/\1.\2/")

# Create environment
START_TIME=$(date +%s)
echo ">=== ${START_TIME} Configuring $ENV_NAME conda environment ===<"
CREATE_EXE=$([[ $(which mamba) ]] && echo "mamba" || echo "conda")
echo "Starting at $(date +'%Y-%m-%d %H:%M:%S')"
echo "Installing $(echo $CONDA_PACKAGES | wc -w) packages with $CREATE_EXE..."
echo "$(echo $CONDA_PACKAGES | tr ' ' '\n' | sort | tr '\n' ' ')"
if [ "$(conda env list | grep $ENV_NAME)" = "" ]; then
    $CREATE_EXE create -y --name $ENV_NAME python=$VERSION $CONDA_PACKAGES
else
    conda install -y --name $ENV_NAME $CONDA_PACKAGES
fi

# Check that environment exists
if [ "$(conda env list | grep $ENV_NAME)" = "" ]; then
    echo "Could not build python $VERSION environment"
    exit 1
fi

# Install pip packages
echo "Installing $(echo $PIP_PACKAGES | wc -w) additional packages with pip..."
echo "$(echo $PIP_PACKAGES | tr ' ' '\n' | sort | tr '\n' ' ')"
/anaconda/envs/${ENV_NAME}/bin/pip install $PIP_PACKAGES

# Check that all requested packages are installed
MISSING_PACKAGES=""
INSTALLED_PACKAGES=$(conda list -n $ENV_NAME | grep -v '^#' | cut -d' ' -f1)
for REQUESTED_PACKAGE in $CONDA_PACKAGES $PIP_PACKAGES; do
    REQUESTED_PACKAGE=$(echo $REQUESTED_PACKAGE| tr '[A-Z' '[a-z]')
    is_installed=0
    for INSTALLED_PACKAGE in $INSTALLED_PACKAGES; do
        if [ "$REQUESTED_PACKAGE" == "$INSTALLED_PACKAGE" ]; then
            is_installed=1
            break
        fi
    done
    if [ $is_installed -eq 0 ]; then
        MISSING_PACKAGES="$MISSING_PACKAGES $REQUESTED_PACKAGE"
    fi
done
if [ "$MISSING_PACKAGES" ]; then
    echo "The following requested packages are missing:\n$MISSING_PACKAGES"
    exit 1
else
    echo "All requested ${ENV_NAME} packages are installed"
fi

# Set the Jupyter kernel name to the full Python version name and store it as $ENV_NAME so that different python3 versions show up separately
PYTHON_VERSION=$(/anaconda/envs/${ENV_NAME}/bin/python --version 2>&1 | cut -d' ' -f2)
sed -i "s|\"display_name\": \"Python.*\"|\"display_name\": \"Python ${PYTHON_VERSION}\"|" /anaconda/envs/${ENV_NAME}/share/jupyter/kernels/python[2,3]/kernel.json
ln -s /anaconda/envs/${ENV_NAME}/share/jupyter/kernels/python[2,3] /anaconda/envs/${ENV_NAME}/share/jupyter/kernels/${ENV_NAME}

# Finish up
ELAPSED=$(date -u -d "0 $(date +%s) seconds - $START_TIME seconds" +"%H:%M:%S")
echo "Finished at $(date +'%Y-%m-%d %H:%M:%S') after $ELAPSED"