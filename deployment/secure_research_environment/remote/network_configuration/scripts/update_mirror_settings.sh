#!/bin/bash
# $CRAN_MIRROR_IP must be present as an environment variable
# $PYPI_MIRROR_IP must be present as an environment variable
# $PYPI_MIRROR_HOST must be present as an environment variable
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

echo "Updating PyPI mirror to point at '$PYPI_MIRROR_HOST'"
echo "" > /etc/pip.conf
echo "[global]" >> /etc/pip.conf
echo "index = ${PYPI_MIRROR_IP}" >> /etc/pip.conf
echo "index-url = ${PYPI_MIRROR_IP}/simple" >> /etc/pip.conf
echo "trusted-host = ${PYPI_MIRROR_HOST}" >> /etc/pip.conf

echo "Updating CRAN mirror to point at '$CRAN_MIRROR_IP'"
echo "" > /etc/R/Rprofile.site
echo "local({" >> /etc/R/Rprofile.site
echo "    r <- getOption(\"repos\")" >> /etc/R/Rprofile.site
echo "    r[\"CRAN\"] <- \"${CRAN_MIRROR_IP}\"" >> /etc/R/Rprofile.site
echo "    options(repos = r)" >> /etc/R/Rprofile.site
echo "})" >> /etc/R/Rprofile.site
# Also update conda environments
for configFile in $(/opt/anaconda/envs/*/lib/R/etc/Rprofile.site 2> /dev/null); do
    cp /etc/R/Rprofile.site $configFile
done
