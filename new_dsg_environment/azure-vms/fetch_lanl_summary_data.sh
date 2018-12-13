#!/usr/bin/env bash

# Constants for colourised output
BOLD="\033[1m"
RED="\033[0;31m"
BLUE="\033[0;36m"
END="\033[0m"

SUMMARY_DATA_DIR=summary-dataset-2017

# Document usage for this script
print_usage_and_exit() {
    echo "usage: $0 -d destination_directory [-h]"
    echo "  -h                        display help"
    echo "  -d destination_directory  specify the directory in which to create a '$SUMMARY_DATA_DIR' containing the LANL summary data"
    exit 1
}

# Read command line arguments, overriding defaults where necessary
while getopts "d:h" opt; do
    case $opt in
        d)
            DESTINATION_DIR=$OPTARG
            ;;
        h)
            print_usage_and_exit
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            ;;
    esac
done

# Check that a DSG group ID has been provided
if [ "$DESTINATION_DIR" = "" ]; then
    echo -e "${RED}Destination directory is a required argument!${END}"
    print_usage_and_exit
fi

MAIN_DIR=$DESTINATION_DIR/$SUMMARY_DATA_DIR
mkdir -p $MAIN_DIR

if [ ! -d "$MAIN_DIR" ]; then
    echo -e "${RED}Failed to create ${BLUE}${SUMMARY_DATA_DIR}${END} directory in ${BLUE}$DESTINATION_DIR${END}"
    print_usage_and_exit
else
    echo "${BOLD}Downloading summary date to ${BLUE}${MAIN_DIR}${END}"
fi

# Fetch red team summary data
mkdir $MAIN_DIR/red_team
wget -c https://dsgimperiallanl.blob.core.windows.net/lanl-data/summary-dataset-2017/red_team/redteam_authentications_summary.txt -O $MAIN_DIR/red_team/redteam_authentications_summary.txt
wget -c https://dsgimperiallanl.blob.core.windows.net/lanl-data/summary-dataset-2017/red_team/redteam_process_summary.txt -O $MAIN_DIR/red_team/redteam_process_summary.txt
wget -c https://dsgimperiallanl.blob.core.windows.net/lanl-data/summary-dataset-2017/red_team/session_hosts.txt -O $MAIN_DIR/red_team/session_hosts.txt


# Fetch daily data
mkdir $MAIN_DIR/wls
mkdir $MAIN_DIR/netflow
for i in $(seq -f "%02g" 1 90); do
    # wls data
    wget -c https://dsgimperiallanl.blob.core.windows.net/lanl-data/summary-dataset-2017/wls/process_wls_summary-${i}.gz -O $MAIN_DIR/wls/authentications_wls_summary-$i.bz2
    wget -c https://dsgimperiallanl.blob.core.windows.net/lanl-data/summary-dataset-2017/wls/process_wls_summary-${i}.gz -O $MAIN_DIR/wls/process_wls_summary-$i.bz2
    # netflow data (missing for day 01)
    if [ "$i" != "01" ]; then
      wget -c https://dsgimperiallanl.blob.core.windows.net/lanl-data/summary-dataset-2017/netflow/netflow_summary-${i}.gz -O $MAIN_DIR/netflow/netflow_day-$i.bz2
    fi
done
