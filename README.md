# Mega Web Dav
This container will put out a connection to Mega as a webpage using their support for webdav.  It is a one way connection.  You can also set mega to sync to a particular folder if you want as well.

## Vars 

username - Mega Username

password - Mega Password

sync - (true/false) - Enable directory syncing.  Default: false

## Volumes
/mnt - this is why syncing will write out your files if you have it enabled.