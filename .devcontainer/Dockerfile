ARG VARIANT=3.10
FROM python:${VARIANT}-buster

# Set package versions
ARG AZURE_CLI_VERSION="2.42.0"
ARG PWSH_VERSION="7.2.6"
ARG PULUMI_VERSION="3.45.0"
ARG POETRY_VERSION="1.2.2"

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

# Install Powershell
# Pull different binaries from Github depending on system architecture
# The standard APT method currently only works for `amd64`
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
COPY ./docs/build/requirements.txt /build/requirements.txt
RUN pip3 install -r /build/requirements.txt

# Install/check needed powershell modules
COPY ./deployment/CheckRequirements.ps1 /build/CheckRequirements.ps1
COPY ./deployment/common/Logging.psm1 /build/common/Logging.psm1
RUN pwsh -Command "& {Set-PSRepository -Name PSGallery -InstallationPolicy Trusted}" \
  && pwsh -File /build/CheckRequirements.ps1 -InstallMissing \
  && sudo rm -rf /build/

# Set PATH for pulumi - pulumi installed as feature to work round installing as root
ENV PATH=$PATH:/home/${USERNAME}/.pulumi/bin

# Install poetry
# Respects environment variables $POETRY_HOME and $POETRY_VERSION
RUN curl -sSL https://install.python-poetry.org | python3 - \
  && /home/${USERNAME}/.local/bin/poetry config virtualenvs.in-project true