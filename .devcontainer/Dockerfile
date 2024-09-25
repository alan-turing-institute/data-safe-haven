ARG VARIANT=3.12
ARG DISTRIBUTION="bookworm"
FROM python:${VARIANT}-${DISTRIBUTION}

RUN apt-get update \
    && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends \
        git \
        libssl-dev

# Install Azure-CLI
RUN apt-get update \
    && apt-get -y install --no-install-recommends \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release
RUN mkdir -p /etc/apt/keyrings \
    && curl -sLS https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg \
    && chmod go+r /etc/apt/keyrings/microsoft.gpg

# Set package versions
ARG AZURE_CLI_VERSION="2.64.0"
ARG DISTRIBUTION

# Add the Azure CLI repository
RUN cat <<EOF > /etc/apt/sources.list.d/azure-cli.sources
Types: deb
URIs: https://packages.microsoft.com/repos/azure-cli/
Suites: $(lsb_release -cs)
Components: main
Architectures: $(dpkg --print-architecture)
Signed-by: /etc/apt/keyrings/microsoft.gpg
EOF

RUN apt-get update \
   && apt-get -y install azure-cli=${AZURE_CLI_VERSION}-1~${DISTRIBUTION}

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

# Set PATH for pulumi - pulumi installed as feature to work round installing as root
ENV PATH=$PATH:/home/${USERNAME}/.pulumi/bin

# Install hatch to build the dsh cli tool
RUN pip3 install hatch