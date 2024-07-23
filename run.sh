/usr/bin/mega-cmd-server &
/usr/bin/mega-login $username $password
/usr/bin/mega-webdav --public /
if [ $sync = true ] ; then
    uuid > /etc/machine-id
    /usr/bin/mega-sync /mnt /
fi
sleep infinity