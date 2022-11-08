ARG VARIANT=3.10
FROM python:${VARIANT}-buster

ARG DOCKER_BUILDKIT=1

ARG TARGETARCH
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends libssl-dev git

# Install Azure-CLI - DOES NOT SUPPORT ARM64 ON LINUX
ARG AZURE_CLI_VERSION="2.42.0"
RUN apt-get update \
  && apt-get -y install ca-certificates curl \ 
  apt-transport-https lsb-release gnupg \
  && curl -sL https://packages.microsoft.com/keys/microsoft.asc \ 
  | gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null \
  && AZ_REPO="$(lsb_release -cs)" \
  && echo "deb [arch=$(dpkg --print-architecture)] https://packages.microsoft.com/repos/azure-cli/ $AZ_REPO main" \ 
  | tee /etc/apt/sources.list.d/azure-cli.list \
  && apt-get update \
  && apt-get -y install azure-cli="${AZURE_CLI_VERSION}-1~buster"

# Install Powershell
RUN if [ "${TARGETARCH}" = "arm64" ]; \
  then \
    DEBARCH="arm64"; \
  else \
    DEBARCH="x86"; \
  fi; \
  curl -L -o /tmp/powershell.tar.gz https://github.com/PowerShell/PowerShell/releases/download/v7.2.3/powershell-7.2.3-linux-$DEBARCH.tar.gz \
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

# Install/check needed powershell modules
ADD install_pwsh_modules.ps1 /build/install_pwsh_modules.ps1
RUN pwsh -File '/build/install_pwsh_modules.ps1' && sudo rm -rf /build/

