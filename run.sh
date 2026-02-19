#!/bin/bash

MONITOR_INTERVAL=60

cleanup() {
    echo "Shutting down..."
    MONITOR_PID="" # prevent monitor cleanup race
    /usr/bin/mega-quit
    exit 0
}
trap cleanup SIGTERM SIGINT

mkdir -p /root/.megaCmd
chown root:root /root/.megaCmd
chmod 700 /root/.megaCmd
rm -rf /root/.megaCmd/apiFolder_*

echo "Starting mega-cmd-server..."
/usr/bin/mega-cmd-server --skip-lock-check &
until mega-version >/dev/null 2>&1; do sleep 1; done
echo "mega-cmd-server is ready."

echo "Logging in..."
if /usr/bin/mega-login "$username" "$password"; then
    echo "Login successful."
else
    echo "Login FAILED."
    exit 1
fi

echo "Starting WebDAV..."
/usr/bin/mega-webdav --public /
chmod 775 /mnt

if [ "$sync" = true ]; then
    echo "Generating machine-id..."
    uuid > /etc/machine-id

    echo "Starting sync of / to /mnt..."
    /usr/bin/mega-sync /mnt /
    echo "Sync command exit code: $?"

    # Monitor loop: fix sync issues and handle quota problems
    while true; do
        sleep "$MONITOR_INTERVAL"

        # Check sync status
        sync_status=$(/usr/bin/mega-sync 2>/dev/null)
        run_state=$(echo "$sync_status" | tail -n1 | awk '{print $4}')
        error_field=$(echo "$sync_status" | tail -n1 | sed -n 's/.*\(Reached storage quota limit\).*/\1/p')

        # Handle quota-disabled sync: delete locally removed files from MEGA
        if [ -n "$error_field" ]; then
            echo "[monitor] Sync disabled due to storage quota. Checking for local deletions to propagate..."
            while IFS= read -r remote_file; do
                [ -z "$remote_file" ] && continue
                local_file="/mnt/$remote_file"
                if [ ! -e "$local_file" ]; then
                    echo "[monitor] File deleted locally, removing from MEGA: $remote_file"
                    /usr/bin/mega-rm "/$remote_file" 2>&1
                fi
            done < <(/usr/bin/mega-ls / 2>/dev/null)

            # Re-enable sync after freeing space
            echo "[monitor] Re-enabling sync..."
            sync_id=$(echo "$sync_status" | tail -n1 | awk '{print $1}')
            if [ -n "$sync_id" ]; then
                /usr/bin/mega-sync -d "$sync_id" 2>/dev/null
                /usr/bin/mega-sync /mnt / 2>/dev/null
                echo "[monitor] Sync re-registered."
            fi
            continue
        fi

        # Handle sync issues (bad fingerprints, etc.): fall back to mega-get
        issues=$(/usr/bin/mega-sync-issues --limit=0 2>/dev/null)
        if echo "$issues" | grep -q "Can't download"; then
            echo "[monitor] Sync issues detected, attempting mega-get fallback..."
            echo "$issues" | grep "Can't download" | while IFS= read -r line; do
                # Extract filename from: Can't download 'filename' to the selected location
                filename=$(echo "$line" | sed "s/.*Can't download '\\(.*\\)' to the selected location.*/\\1/")
                if [ -n "$filename" ] && [ ! -f "/mnt/$filename" ]; then
                    echo "[monitor] Downloading via mega-get: $filename"
                    if /usr/bin/mega-get "/$filename" /mnt/ 2>&1; then
                        echo "[monitor] Successfully downloaded: $filename"
                    else
                        echo "[monitor] Failed to download: $filename (may be transfer quota)"
                    fi
                fi
            done
        fi

        # Log current sync state periodically
        file_count=$(ls -1 /mnt/ 2>/dev/null | wc -l)
        echo "[monitor] Sync state: $run_state | Local files: $file_count"
    done &
    MONITOR_PID=$!
else
    echo "Sync is disabled (sync=$sync)."
fi

echo "Startup complete. Waiting..."
wait
