#!/bin/bash

MONITOR_INTERVAL=60
QUOTA_COOLDOWN_SECONDS=3600
SOFT_REFRESH_THRESHOLD=5
HARD_REFRESH_THRESHOLD=5
HARD_REFRESH_MIN_INTERVAL=1800

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

start_server_and_login() {
    echo "Starting mega-cmd-server..."
    /usr/bin/mega-cmd-server --skip-lock-check &
    until mega-version >/dev/null 2>&1; do sleep 1; done
    echo "mega-cmd-server is ready."

    echo "Logging in..."
    if /usr/bin/mega-login "$username" "$password"; then
        echo "Login successful."
        return 0
    else
        echo "Login FAILED."
        return 1
    fi
}

attach_services() {
    echo "Starting WebDAV..."
    /usr/bin/mega-webdav --public /
    chmod 775 /mnt

    if [ "$sync" = true ]; then
        echo "Generating machine-id..."
        uuid > /etc/machine-id

        echo "Starting sync of / to /mnt..."
        /usr/bin/mega-sync /mnt /
        echo "Sync command exit code: $?"
    else
        echo "Sync is disabled (sync=$sync)."
    fi
}

is_quota_message() {
    echo "$1" | grep -qiE 'bandwidth quota|transfer quota|Transfer not started'
}

is_account_details_failure() {
    echo "$1" | grep -q 'Failed to get account details'
}

is_stale_quota_message() {
    # "try again in -N seconds": quota window has already passed but
    # mega-cmd is still reporting it. Indicates stale server state.
    echo "$1" | grep -qE 'try again in -[0-9]+ seconds'
}

do_soft_refresh() {
    echo "[monitor] Account-details errors persisting; soft refresh (logout/login)"
    /usr/bin/mega-logout
    /usr/bin/mega-login "$username" "$password"
    account_details_failures=0
    soft_refresh_attempted=1
}

do_hard_refresh() {
    echo "[monitor] Hard refresh (server restart + cache wipe)"
    /usr/bin/mega-quit 2>/dev/null
    sleep 2
    rm -rf /root/.megaCmd/apiFolder_*
    start_server_and_login
    attach_services
    account_details_failures=0
    soft_refresh_attempted=0
    hard_refresh_attempted_at=$(date +%s)
    quota_cooldown_until=0
    quota_rescan_pending=0
}

do_sync_rescan() {
    # Force mega-cmd to re-enumerate the sync after a quota event.
    # Why: pause/resume only resumes from checkpoint; remove + re-add is the
    # only mechanism that retries items abandoned during quota exhaustion.
    local sync_id
    sync_id=$(/usr/bin/mega-sync 2>/dev/null | tail -n1 | awk '{print $1}')
    if [ -z "$sync_id" ] || [ "$sync_id" = "ID" ]; then
        echo "[monitor] Sync rescan skipped: no active sync found"
        return
    fi
    echo "[monitor] Sync rescan: removing sync ID=$sync_id"
    /usr/bin/mega-sync -d "$sync_id"
    echo "[monitor] Sync rescan: re-adding /mnt <-> /"
    /usr/bin/mega-sync /mnt /
    echo "[monitor] Sync rescan complete"
}

if ! start_server_and_login; then
    exit 1
fi
attach_services

if [ "$sync" = true ]; then
    quota_cooldown_until=0
    quota_rescan_pending=0
    account_details_failures=0
    soft_refresh_attempted=0
    hard_refresh_attempted_at=0

    while true; do
        sleep "$MONITOR_INTERVAL"
        now=$(date +%s)
        force_hard_refresh=0

        df_output=$(/usr/bin/mega-df -h 2>&1)
        if is_account_details_failure "$df_output"; then
            account_details_failures=$((account_details_failures + 1))
            session_state="stale($account_details_failures)"
        else
            account_details_failures=0
            session_state="ok"
        fi

        if is_quota_message "$df_output"; then
            if [ "$now" -ge "$quota_cooldown_until" ]; then
                echo "[monitor] Bandwidth quota exhausted (detected via mega-df); backing off for ${QUOTA_COOLDOWN_SECONDS}s"
            fi
            quota_cooldown_until=$((now + QUOTA_COOLDOWN_SECONDS))
            quota_rescan_pending=1
        fi

        if is_stale_quota_message "$df_output"; then
            echo "[monitor] Stale quota state detected via mega-df (negative retry seconds); forcing hard refresh"
            force_hard_refresh=1
        fi

        sync_status=$(/usr/bin/mega-sync 2>/dev/null)
        run_state=$(echo "$sync_status" | tail -n1 | awk '{print $4}')

        if [ "$now" -lt "$quota_cooldown_until" ]; then
            remaining=$((quota_cooldown_until - now))
            quota_state="exhausted(cooldown ${remaining}s)"
        else
            quota_state="ok"
            issues=$(/usr/bin/mega-sync-issues --limit=0 2>/dev/null)
            if echo "$issues" | grep -q "Can't download"; then
                echo "[monitor] Sync issues detected, attempting mega-get fallback..."
                while IFS= read -r line; do
                    filename=$(echo "$line" | sed "s/.*Can't download '\\(.*\\)' to the selected location.*/\\1/")
                    if [ -n "$filename" ] && [ ! -f "/mnt/$filename" ]; then
                        echo "[monitor] Downloading via mega-get: $filename"
                        get_output=$(/usr/bin/mega-get "/$filename" /mnt/ 2>&1)
                        get_rc=$?
                        echo "$get_output"
                        if [ "$get_rc" -eq 0 ]; then
                            echo "[monitor] Successfully downloaded: $filename"
                        else
                            echo "[monitor] Failed to download: $filename"
                            # Check stale-quota first: negative retry seconds is unambiguous
                            # phantom state, and the account-details error often appears alongside
                            # it. Order matters — otherwise we loop forever bumping a counter
                            # that resets each iteration when mega-df succeeds.
                            if is_stale_quota_message "$get_output"; then
                                echo "[monitor] Stale quota state detected in mega-get output (negative retry seconds); forcing hard refresh"
                                force_hard_refresh=1
                                break
                            fi
                            if is_account_details_failure "$get_output"; then
                                account_details_failures=$((account_details_failures + 1))
                                echo "[monitor] Stale session detected in mega-get output (failures=$account_details_failures)"
                                break
                            fi
                            if is_quota_message "$get_output"; then
                                quota_cooldown_until=$((now + QUOTA_COOLDOWN_SECONDS))
                                quota_rescan_pending=1
                                quota_state="exhausted(cooldown ${QUOTA_COOLDOWN_SECONDS}s)"
                                echo "[monitor] Bandwidth quota detected on mega-get; backing off for ${QUOTA_COOLDOWN_SECONDS}s"
                                break
                            fi
                        fi
                    fi
                done < <(echo "$issues" | grep "Can't download")
            fi
        fi

        if [ "$force_hard_refresh" -eq 1 ]; then
            if [ "$((now - hard_refresh_attempted_at))" -lt "$HARD_REFRESH_MIN_INTERVAL" ]; then
                echo "[monitor] Hard refresh requested but recently attempted; suppressing"
            else
                do_hard_refresh
            fi
        elif [ "$account_details_failures" -ge "$SOFT_REFRESH_THRESHOLD" ] && [ "$soft_refresh_attempted" -eq 0 ]; then
            do_soft_refresh
        elif [ "$account_details_failures" -ge "$HARD_REFRESH_THRESHOLD" ] && [ "$soft_refresh_attempted" -eq 1 ]; then
            if [ "$((now - hard_refresh_attempted_at))" -lt "$HARD_REFRESH_MIN_INTERVAL" ]; then
                echo "[monitor] Hard refresh recently attempted; suppressing"
            else
                do_hard_refresh
            fi
        elif [ "$quota_rescan_pending" -eq 1 ] && [ "$now" -ge "$quota_cooldown_until" ]; then
            echo "[monitor] Quota cooldown ended; forcing sync rescan to retry abandoned items"
            do_sync_rescan
            quota_rescan_pending=0
        fi

        file_count=$(ls -1 /mnt/ 2>/dev/null | wc -l)
        echo "[monitor] state=${run_state:-?} files=$file_count quota=$quota_state session=$session_state"
    done &
    MONITOR_PID=$!
fi

echo "Startup complete. Waiting..."
wait
