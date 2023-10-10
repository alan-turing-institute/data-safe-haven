ARG VARIANT=3.10
FROM python:${VARIANT}-buster

# Set package versions
ARG AZURE_CLI_VERSION="2.42.0"
ARG PULUMI_VERSION="3.80.0"

RUN apt-get update \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
      git \
      libssl-dev \
      python3-sphinx

# Set up TARGETARCH variable to use to pull the right binaries
# for the current architecture.
ARG TARGETARCH

# Install Azure-CLI
# Standard install method currently does not support ARM64
# Use pip instead - https://github.com/Azure/azure-cli/issues/22875
RUN pip3 install azure-cli==${AZURE_CLI_VERSION}
RUN pip3 install hatch

# Create non-root user and give them sudo access
ARG USERNAME=deploydsh
ARG USER_UID=1000
ARG USER_GID=$USER_UID
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Set the default user
USER $USERNAME

# Install Sphinx dependencies
COPY ./docs/requirements.txt /build/requirements.txt
RUN pip3 install -r /build/requirements.txt

# Set PATH for pulumi - pulumi installed as feature to work round installing as root
ENV PATH=$PATH:/home/${USERNAME}/.pulumi/bin
