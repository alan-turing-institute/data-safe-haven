#!/bin/sh
print_usage_and_exit() {
    echo "usage: $0 [-h] -q"
    echo "  -h      display help"
    echo "  -q      host to query DNS for (e.g. rdssh1.dsgroup9.co.uk)"
    exit 1
}

while getopts "h?q:" opt; do
    case "$opt" in
        h|\?)
            print_usage_and_exit
            ;;
        q)  
            TEST_HOST=$OPTARG
            ;;
    esac
done

NS_CMD=( nslookup $TEST_HOST )
RESTART_CMD="sudo systemctl restart systemd-resolved.service"

NS_RESULT_PRE=$(${NS_CMD[@]})
NS_EXIT_PRE=$?
if [ "$NS_EXIT_PRE" == "0" ]
then
    # Nslookup succeeded: no need to restart name resolution service
    echo "Name resolution working. No need to restart."
    echo "NS LOOKUP RESULT:"
    echo "$NS_RESULT_PRE"
    exit 0
else
    # Nslookup failed: try restarting name resolution service
    echo "Name resolution not working. Restarting name resolution service."
    echo "NS LOOKUP RESULT:"
    echo "$NS_RESULT_PRE"
    $(${RESTART_CMD})
fi

NS_RESULT_POST=$(${NS_CMD[@]})
NS_EXIT_POST=$?
if [ "$NS_EXIT_POST" == "0" ]
then
    # Nslookup succeeded: name resolution service successfully restarted
    echo "Name resolution working. Restart successful."
    echo "NS LOOKUP RESULT:"
    echo $NS_RESULT_POST
    exit 0
else
    # Nslookup failed: print notification and exit
    echo "Name resolution not working after restart."
    echo "NS LOOKUP RESULT:"
    echo "$NS_RESULT_POST"
    echo "Restart command: $RESTART_CMD"
    exit 1
fi
