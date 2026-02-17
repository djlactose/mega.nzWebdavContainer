#!/bin/bash

cleanup() {
    /usr/bin/mega-quit
    exit 0
}
trap cleanup SIGTERM SIGINT

mkdir -p /root/.megaCmd
chown root:root /root/.megaCmd
chmod 700 /root/.megaCmd
rm -rf /root/.megaCmd/apiFolder_*

/usr/bin/mega-cmd-server &
until mega-ls / >/dev/null 2>&1; do sleep 1; done

/usr/bin/mega-login "$username" "$password" || exit 1
/usr/bin/mega-webdav --public /
chmod 775 /mnt

if [ "$sync" = true ]; then
    uuid > /etc/machine-id
    /usr/bin/mega-sync /mnt /
fi

wait
