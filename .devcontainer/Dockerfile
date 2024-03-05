ARG VARIANT=3.10
FROM python:${VARIANT}-buster

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends apt-transport-https \
    ca-certificates \
    curl \
    git \
    gnupg \
    libssl-dev \
    lsb-release \
    python3-sphinx \
    sudo
    
# Set package versions
ARG AZURE_CLI_VERSION="2.53.1"
ARG PWSH_VERSION="7.4.1"

# Install Azure-CLI 
# Get Microsoft signing key
RUN sudo mkdir -p /etc/apt/keyrings \
  && curl -sLS https://packages.microsoft.com/keys/microsoft.asc | \
      gpg --dearmor | \
      sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null \
  && sudo chmod go+r /etc/apt/keyrings/microsoft.gpg \
  && AZ_DIST=$(lsb_release -cs) \
  && echo "deb [arch=`dpkg --print-architecture` signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $AZ_DIST main" | \
      sudo tee /etc/apt/sources.list.d/azure-cli.list \
  && sudo apt-get update \
  && sudo apt-get install azure-cli=$AZURE_CLI_VERSION-1~$AZ_DIST

# Install Powershell
# Pull different binaries from Github depending on system architecture
# The standard APT method currently only works for `amd64`
# Set up TARGETARCH variable to use to pull the right binaries for the current architecture.
ARG TARGETARCH
RUN if [ "${TARGETARCH}" = "arm64" ]; \
  then \
    DEBARCH="arm64"; \
  else \
    DEBARCH="x86"; \
  fi; \
  curl -L -o /tmp/powershell.tar.gz https://github.com/PowerShell/PowerShell/releases/download/v${PWSH_VERSION}/powershell-${PWSH_VERSION}-linux-$DEBARCH.tar.gz \
  && mkdir -p /opt/microsoft/powershell/7 \
  && tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 \
  && chmod +x /opt/microsoft/powershell/7/pwsh \
  && ln -s /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh

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

# Install/check needed powershell modules
COPY ./deployment/CheckRequirements.ps1 /build/CheckRequirements.ps1
COPY ./deployment/common/Logging.psm1 /build/common/Logging.psm1
RUN pwsh -Command "& {Set-PSRepository -Name PSGallery -InstallationPolicy Trusted}" \
  && pwsh -File /build/CheckRequirements.ps1 -InstallMissing  -IncludeDev\
  && sudo rm -rf /build/
