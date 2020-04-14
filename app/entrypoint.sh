#! /bin/ash
# start cron
crond -f -l 1 &
# rogrotate
logrotate -d /etc/logrotate.conf &
# start sinatra server
rackup &
# start apache
httpd-foreground
