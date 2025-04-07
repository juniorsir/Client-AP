#!/bin/bash
WATCH_DIR="/home/your_username/printjobs"

inotifywait -m "$WATCH_DIR" -e create |
while read path action file; do
    if [[ "$file" == *.pdf ]]; then
        echo "[PRINTING] $file"
        lp "$WATCH_DIR/$file"
    fi
done
