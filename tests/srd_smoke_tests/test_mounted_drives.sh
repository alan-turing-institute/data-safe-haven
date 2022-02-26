#! /bin/bash
while getopts d: flag
do
    case "${flag}" in
        d) directory=${OPTARG};;
    esac
done

nfailed=0
if [[ "$directory" = "home" ]]; then directory_path=$(echo ~); else directory_path="/${directory}"; fi
testfile="$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)"

# Check that directory exists
if [ "$(ls ${directory_path} 2>&1 1>/dev/null)" ]; then
    echo "Could not find mount '${directory_path}'"
    nfailed=$((nfailed + 1))
fi

# Test operations
CAN_CREATE="$([[ "$(touch ${directory_path}/${testfile} 2>&1 1>/dev/null)" = "" ]] && echo '1' || echo '0')"
CAN_WRITE="$([[ -w ${directory_path}/${testfile} ]] && echo '1' || echo '0')"
CAN_DELETE="$([[ "$(touch ${directory_path}/${testfile} 2>&1 1>/dev/null | rm ${directory_path}/${testfile} 2>&1)" ]] && echo '0' || echo '1')"

# Check that permissions are as expected for each directory
case "$directory" in
    data)
        if [ $CAN_CREATE = 1 ]; then echo "Able to create files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        if [ $CAN_WRITE = 1 ]; then echo "Able to write files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        if [ $CAN_DELETE = 1 ]; then echo "Able to delete files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        ;;

    home)
        if [ $CAN_CREATE = 0 ]; then echo "Unable to create files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        if [ $CAN_WRITE = 0 ]; then echo "Unable to write files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        if [ $CAN_DELETE = 0 ]; then echo "Unable to delete files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        ;;

    output)
        if [ $CAN_CREATE = 0 ]; then echo "Unable to create files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        if [ $CAN_WRITE = 0 ]; then echo "Unable to write files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        if [ $CAN_DELETE = 0 ]; then echo "Unable to delete files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        ;;

    shared)
        if [ $CAN_CREATE = 0 ]; then echo "Unable to create files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        if [ $CAN_WRITE = 0 ]; then echo "Unable to write files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        if [ $CAN_DELETE = 0 ]; then echo "Unable to delete files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        ;;

    scratch)
        if [ $CAN_CREATE = 0 ]; then echo "Unable to create files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        if [ $CAN_WRITE = 0 ]; then echo "Unable to write files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        if [ $CAN_DELETE = 0 ]; then echo "Unable to delete files in ${directory_path}!"; nfailed=$((nfailed + 1)); fi
        ;;

    *)
        echo "Usage: $0 -d [directory]"
        exit 1
esac

# Cleanup and print output
rm -rf "${directory_path}/${testfile}" 2> /dev/null
if [ $nfailed = 0 ]; then
    echo "All tests passed for '${directory_path}'"
else
    echo "$nfailed tests failed for '${directory_path}'!"
fi
