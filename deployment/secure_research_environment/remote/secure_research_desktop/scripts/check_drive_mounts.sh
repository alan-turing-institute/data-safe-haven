#! /bin/bash
# This script is designed to be deployed to an Azure Linux VM via
# the Powershell Invoke-AzVMRunCommand, which sets all variables
# passed in its -Parameter argument as environment variables

RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

MOUNT_POINTS=("/data" "/home" "/scratch" "/shared" "/output")
echo -e "${BLUE}Checking drives are mounted...${END}"
for MOUNT_POINT in "${MOUNT_POINTS[@]}"; do
    ls "${MOUNT_POINT}"/* > /dev/null 2>&1
    if (findmnt "$MOUNT_POINT" > /dev/null 2>&1); then
        echo -e "${BLUE} [o] ${MOUNT_POINT} is mounted...${END}"
    else
        echo -e "${RED} [ ] ${MOUNT_POINT} not mounted. Attempting to mount...${END}"
        MOUNT_UNIT="$(echo "$MOUNT_POINT" | tr -d '/').mount"
        if [ -e "/etc/systemd/system/${MOUNT_UNIT}" ]; then
            systemctl start "${MOUNT_UNIT}"
        else
            mount "$MOUNT_POINT"
        fi
    fi
done
sleep 30

echo -e "${BLUE}Rechecking drives are mounted...${END}"
for MOUNT_POINT in "${MOUNT_POINTS[@]}"; do
    ls "${MOUNT_POINT}"/* > /dev/null 2>&1
    if (findmnt "$MOUNT_POINT" > /dev/null 2>&1); then
        echo -e "${BLUE} [o] ${MOUNT_POINT} is mounted...${END}"
        df -h  | grep "$MOUNT_POINT"
    else
        echo -e "${RED} [x] ${MOUNT_POINT} is not currently mounted...${END}"
    fi
done
