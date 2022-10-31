#ARG VARIANT="jammy"
FROM mcr.microsoft.com/powershell:7.2-ubuntu-bionic
# [Optional] Uncomment this section to install additional OS packages.
RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
    && apt-get -y install --no-install-recommends libssl-dev

# Install azure-cli
RUN apt-get update && apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg \
    && curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
    gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null \
    && AZ_REPO=$(lsb_release -cs) \
    && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ ${AZ_REPO} main" | tee /etc/apt/sources.list.d/azure-cli.list \
    && apt-get update && apt-get install azure-cli

# Install/check needed powershell modules
ADD install_pwsh_modules.ps1 /build/install_pwsh_modules.ps1
RUN pwsh -File '/build/install_pwsh_modules.ps1' && rm -rf /build/
