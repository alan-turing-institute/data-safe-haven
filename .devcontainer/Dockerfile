ARG VARIANT=3.12
FROM python:${VARIANT}-rc-alpine

RUN apk add --no-cache shadow git gcc musl-dev \ 
    libffi-dev openssl-dev cargo make
# install Azure-CLI
RUN pip install --upgrade pip && pip install azure-cli

# Install Powershell
RUN apk add --no-cache ca-certificates less ncurses-terminfo-base \
    krb5-libs libgcc libintl libssl1.1 libstdc++ tzdata \
    userspace-rcu zlib icu-libs curl

# RUN apt-get update && export DEBIAN_FRONTEND=noninteractive \
#     && apt-get -y install --no-install-recommends libssl-dev git

# # Install azure-cli
# RUN apt-get update && apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg \
#     && curl -sL https://packages.microsoft.com/keys/microsoft.asc | \
#     gpg --dearmor | tee /etc/apt/trusted.gpg.d/microsoft.gpg > /dev/null \
#     && AZ_REPO=$(lsb_release -cs) \
#     && echo "deb [arch=amd64] https://packages.microsoft.com/repos/azure-cli/ ${AZ_REPO} main" | tee /etc/apt/sources.list.d/azure-cli.list \
#     && apt-get update && apt-get install azure-cli

ARG USERNAME=deploydsh
# ARG USER_UID=1000
# ARG USER_GID=$USER_UID

RUN apk add sudo \
 && adduser -g "${USERNAME}" $USERNAME \
 && mkdir -p /etc/sudoers.d \
 && echo "$USERNAME ALL=(ALL) ALL" > /etc/sudoers.d/$USERNAME \
 && chmod 0440 /etc/sudoers.d/${USERNAME}

USER ${USERNAME}

# # Create the user and give them sudo access
# RUN groupadd --gid $USER_GID $USERNAME \
#     && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
#     && apt-get update \
#     && apt-get install -y sudo \
#     && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
#     && chmod 0440 /etc/sudoers.d/$USERNAME

# # Set the default user
# USER $USERNAME

# # Install/check needed powershell modules
# ADD install_pwsh_modules.ps1 /build/install_pwsh_modules.ps1
# RUN pwsh -File '/build/install_pwsh_modules.ps1' && sudo rm -rf /build/
