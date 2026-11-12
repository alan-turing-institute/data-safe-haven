#!/usr/bin/env bash
# Exit successfully once AdGuard Home answers DNS queries on this VM.
# Run as an Azure managed run command so dependent resources wait for DNS.
MAX_ATTEMPTS=60
SLEEP_SECONDS=10

# A non-zero exit code here only signals cloud-init warnings or errors
cloud-init status --wait > /dev/null || echo "cloud-init finished with warnings or errors"

for attempt in $(seq 1 "$MAX_ATTEMPTS"); do
    # dig exits with 0 on any DNS reply (including NXDOMAIN) and 9 on no reply
    if systemctl is-active --quiet adguardhome && dig @127.0.0.1 +time=2 +tries=1 readiness-check.invalid > /dev/null; then
        echo "DNS server ready after ${attempt} attempt(s)"
        exit 0
    fi
    sleep "$SLEEP_SECONDS"
done

echo "DNS server not ready after $((MAX_ATTEMPTS * SLEEP_SECONDS)) seconds" >&2
exit 1
