#!/bin/bash

LOG_FILE="/var/log/dir_monitor.log"
MONITOR_DIR="/var/www/html"

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    FILE_COUNT=$(find "$MONITOR_DIR" -type f | wc -l)
    TOTAL_SIZE=$(du -sh "$MONITOR_DIR" | awk '{print $1}')
    
    echo "$TIMESTAMP - Files: $FILE_COUNT, Size: $TOTAL_SIZE" >> "$LOG_FILE"
	echo "$TIMESTAMP - Files: $FILE_COUNT, Size: $TOTAL_SIZE"
	echo "**************************************************"
    
    sleep 60
done