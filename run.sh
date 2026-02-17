#!/bin/bash

cleanup() {
    echo "Shutting down..."
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
else
    echo "Sync is disabled (sync=$sync)."
fi

echo "Startup complete. Waiting..."
wait
