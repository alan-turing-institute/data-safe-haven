#! /bin/bash

# Require three arguments: environment name; (quoted) list of conda packages; (quoted) list of pip packages
if [ $# -ne 3 ]; then
    exit 1
fi
ENV_NAME=$1
CONDA_PACKAGES=$2
PIP_PACKAGES=$3

# Set version
VERSION=3.7
if [ "$ENV_NAME" == "py27" ]; then VERSION=2.7; fi
if [ "$ENV_NAME" == "py36" ]; then VERSION=3.6; fi

# Create environment
START_TIME=$(date +%s)
echo ">=== ${START_TIME} Configuring $ENV_NAME conda environment ===<"
echo "Starting at $(date +'%Y-%m-%d %H:%M:%S')"
echo "Installing $(echo $CONDA_PACKAGES | wc -w) packages with conda..."
echo "$(echo $CONDA_PACKAGES | tr ' ' '\n' | sort | tr '\n' ' ')"
if [ "$(conda env list | grep $ENV_NAME)" = "" ]; then
    conda create -y --verbose --name $ENV_NAME python=$VERSION $CONDA_PACKAGES
else
    conda install -y --verbose --name $ENV_NAME $CONDA_PACKAGES
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

# Set the Jupyter kernel name to the full Python version name and store it as $ENV_NAME so that different python3 versions show up separately
PYTHON_VERSION=$(/anaconda/envs/${ENV_NAME}/bin/python --version 2>&1 | cut -d' ' -f2)
sed -i "s|\"display_name\": \"Python.*\"|\"display_name\": \"Python ${PYTHON_VERSION}\"|" /anaconda/envs/${ENV_NAME}/share/jupyter/kernels/python[2,3]/kernel.json
ln -s /anaconda/envs/${ENV_NAME}/share/jupyter/kernels/python[2,3] /anaconda/envs/${ENV_NAME}/share/jupyter/kernels/${ENV_NAME}

# Finish up
ELAPSED=$(date -u -d "0 $(date +%s) seconds - $START_TIME seconds" +"%H:%M:%S")
echo "Finished at $(date +'%Y-%m-%d %H:%M:%S') after $ELAPSED"