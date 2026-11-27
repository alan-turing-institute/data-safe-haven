#!/usr/bin/env bash
# Exit successfully once AdGuard Home answers DNS queries on this VM.
# Run as an Azure managed run command so dependent resources wait for DNS.
POLLING_BUDGET_SECONDS=300
SLEEP_SECONDS=5

# A non-zero exit code here only signals cloud-init warnings or errors
cloud-init status --wait > /dev/null || echo "cloud-init finished with warnings or errors"
CLOUD_INIT_SECONDS=$SECONDS

attempt=0
while ((SECONDS - CLOUD_INIT_SECONDS < POLLING_BUDGET_SECONDS)); do
    attempt=$((attempt + 1))
    # dig exits with 0 on any DNS reply (including NXDOMAIN) and 9 on no reply
    if systemctl is-active --quiet adguardhome && dig @127.0.0.1 +time=2 +tries=1 readiness-check.invalid > /dev/null; then
        echo "DNS server ready after ${attempt} attempt(s)"
        echo "readiness-check: cloud_init_seconds=${CLOUD_INIT_SECONDS} dns_wait_seconds=$((SECONDS - CLOUD_INIT_SECONDS)) total_seconds=${SECONDS} attempts=${attempt}"
        exit 0
    fi
    sleep "$SLEEP_SECONDS"
done

echo "DNS server not ready after ${POLLING_BUDGET_SECONDS} seconds" >&2
echo "readiness-check: cloud_init_seconds=${CLOUD_INIT_SECONDS} dns_wait_seconds=$((SECONDS - CLOUD_INIT_SECONDS)) total_seconds=${SECONDS} attempts=${attempt}" >&2
exit 1
