#!/bin/bash
# Update PyPI and CRAN repository settings
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables
#
# The following variables are expected by the script
#     CRAN_MIRROR_INDEX_URL
#     PYPI_MIRROR_IP
#     PYPI_MIRROR_HOST

# Update PyPI
#------------
echo "Updating PyPI mirror to point at '$PYPI_MIRROR_INDEX_URL'"
echo "" > /etc/pip.conf
echo "[global]" >> /etc/pip.conf
echo "index = ${PYPI_MIRROR_INDEX}" >> /etc/pip.conf
echo "index-url = ${PYPI_MIRROR_INDEX_URL}" >> /etc/pip.conf
echo "trusted-host = ${PYPI_MIRROR_HOST}" >> /etc/pip.conf


# Update CRAN
#------------
echo "Updating CRAN mirror to point at '$CRAN_MIRROR_INDEX_URL'"
echo "" > /etc/R/Rprofile.site
echo "local({" >> /etc/R/Rprofile.site
echo "    r <- getOption(\"repos\")" >> /etc/R/Rprofile.site
echo "    r[\"CRAN\"] <- \"${CRAN_MIRROR_INDEX_URL}\"" >> /etc/R/Rprofile.site
echo "    options(repos = r)" >> /etc/R/Rprofile.site
echo "})" >> /etc/R/Rprofile.site
