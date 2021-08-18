/usr/bin/mega-cmd-server &
/usr/bin/mega-login $username $password
/usr/bin/mega-webdav --public /
tail -f /dev/random