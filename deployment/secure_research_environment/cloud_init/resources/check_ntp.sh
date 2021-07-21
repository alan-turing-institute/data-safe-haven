#! /bin/bash

# Check timezone and NTP server
echo "Date:          $(date)"
echo "Timezone:      $(timedatectl | grep "Time zone" | cut -d ':' -f 2 | sed -e 's/^[[:space:]]*//')"
echo "NTP status:    $(timedatectl | grep "NTP service" | cut -d ':' -f 2 | sed -e 's/^[[:space:]]*//')"
echo "NTP server(s): $(grep '^NTP=' -h /etc/systemd/timesyncd.conf /etc/systemd/timesyncd.conf.d/*conf 2> /dev/null | grep -v '^#' | cut -d '=' -f2)"

# Check the timesync service
# Note that 'timedatectl show-timesync --all' should be a more informative option but does not work as expected
systemctl status systemd-timesyncd
