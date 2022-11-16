ARG VARIANT=3.10
FROM python:${VARIANT}-buster

RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends libssl-dev git python3-sphinx

# Set package versions
ARG AZURE_CLI_VERSION="2.42.0"
ARG PWSH_VERSION="7.2.6"

# Set up TARGETARCH variable to use to pull the right binaries for the current architecture.
ARG TARGETARCH

# Install Azure-CLI 
# Standard install method currently does not support ARM64.
# Use pip instead - https://github.com/Azure/azure-cli/issues/22875 

# RUN apt-get update \
#   && apt-get -y install ca-certificates curl \ 
#   apt-transport-https lsb-release gnupg \
#   && curl -sL https://packages.microsoft.com/keys/microsoft.asc \ 
#   | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null \
#   && AZ_REPO="$(lsb_release -cs)" \
#   && echo "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" \ 
#   | tee /etc/apt/sources.list.d/azure-cli.list \
#   && apt-get update \
#   && apt-get -y install azure-cli="${AZURE_CLI_VERSION}-1~buster"

RUN pip3 install azure-cli==${AZURE_CLI_VERSION} 

# Install Powershell
# Pull different binaries from Github depending on architecture.
# The standard APT method only works for `amd64`
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

# Install Sphinx dependencies.
ADD requirements.txt /build/requirements.txt
RUN pip3 install -r /build/requirements.txt

# Install/check needed powershell modules
ADD install_pwsh_modules.ps1 /build/install_pwsh_modules.ps1
RUN pwsh -File '/build/install_pwsh_modules.ps1' && sudo rm -rf /build/

