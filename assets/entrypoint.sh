#! /bin/ash
# start cron
crond -f -l 1
# rogrotate
logrotate -d /etc/logrotate.conf
# start apache
./httpd-foreground
