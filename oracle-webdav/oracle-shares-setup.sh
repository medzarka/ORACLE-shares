######################### Script to Install Alpine 3.19 on Oracle-shares #############################
# ------------------------------------------------------------------------------------------------------------------

## ------------------------------------------------------------------------
# NOTE # Step 1 - install ubuntu 22.04 on oracle cloud

## ------------------------------------------------------------------------
# NOTE # Step 2 - switch from Ubuntu 22.04 to Alpine 3.19
# steps from https://gist.github.com/unixfox/05d661094e646947c4b303f19f9bae11

# [x] S1 - Install Alpine 3.19 inplace of Ubuntu 22.04
wget https://dl-cdn.alpinelinux.org/alpine/v3.19/releases/x86_64/alpine-virt-3.19.0-x86_64.iso
sudo dd if=alpine-virt-3.19.0-x86_64.iso of=/dev/sda
sudo passwd ubuntu # create a ubuntu user password

# manual: On the Oracle Cloud panel, setup a **console connection** and connect to the serial console. Then execute:
sudo reboot
#When Alpine is launched and you are logged in as root, execute these commands in the serial console:
mkdir /media/setup
cp -a /media/sda/* /media/setup
mkdir /lib/setup
cp -a /.modloop/* /lib/setup
/etc/init.d/modloop stop
umount /dev/sda
mv /media/setup/* /media/sda/
mv /lib/setup/* /.modloop/
setup-alpine
# - create the abc user
reboot

## ------------------------------------------------------------------------
# [x] S2 - Connect to the root user
echo "If the current user is not root, then connect to root ..."
doas su

## ------------------------------------------------------------------------
# [x] S3 - Update the system
echo "Configure the alpine repositories and update the system ..."
sed -i 's/#http/http/g' /etc/apk/repositories # enable community repository
apk update
apk upgrade --no-cache --available

## ------------------------------------------------------------------------
# [x] S4 - Install required packages
echo "Install required softwares ..."
apk --no-cache add neofetch htop chrony doas tzdata nano 

## ------------------------------------------------------------------------
# [x] S5 - Configure NTP
echo "setup time zone and NTP ..."
setup-timezone -z Asia/Riyadh
rc-update add chronyd default # NTP synchronization

## ------------------------------------------------------------------------
# [x] S6 - Update user's password
# First step, create two passwords from PVE01 using the pass manager and put them in two files as follows.
ROOT_PASSWORD=$(cat /root/secret_root.txt)
ABC_PASSWORD=$(cat /root/secret_abc.txt)
echo "Update root password ..."
echo "root:$ROOT_PASSWORD" | chpasswd
echo "Update abc password ..."
echo "abc:$ABC_PASSWORD" | chpasswd

## ------------------------------------------------------------------------
# [x] S7 - Configure the firewall
echo "Configure the firewall (by default, accept only key-based ssh connections only) ..."
# Hardening Alpine
apk --no-cache add ufw
ufw default deny incoming
ufw default allow outgoing
ufw limit SSH         # open SSH port and protect against brute-force login attacks
#ufw allow out 123/udp # allow outgoing NTP (Network Time Protocol)

# The following instructions will allow apk to work:
#ufw allow out DNS     # allow outgoing DNS
#ufw allow out 80/tcp  # allow outgoing HTTP traffic
#ufw allow out 443/tcp  # allow pcloud webdav access

#  enabling ufw
ufw enable
rc-service ufw restart
rc-update add ufw default

## ------------------------------------------------------------------------
# [x] S8 - Hardening the SSH service access
echo "Hardening the SSH service access ..."
# Hardening SSH
sed -r -i 's/^#?UseDNS.*/UseDNS no/g' /etc/ssh/sshd_config # By setting this to no, connection speed can increase.
sed -r -i 's/^#?PermitEmptyPasswords.*/PermitEmptyPasswords no/g' /etc/ssh/sshd_config
sed -r -i 's/^#?X11Forwarding.*/X11Forwarding no/g' /etc/ssh/sshd_config
sed -r -i 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/g' /etc/ssh/sshd_config
sed -r -i 's/^#?PermitRootLogin.*/PermitRootLogin no/g' /etc/ssh/sshd_config 
sed -r -i 's/^#?PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config # Do not allow password authentication.

# IMPORTANT :
# before restarting the sshd service, add the ssh key from the client.
# >> on the client side:
# ssh-keygen -P "" -m PEM -t rsa -b 4096 -C "medzarka@gmail.com"  # create ssh key pair for the new user
# ssh-copy-id abc@<SERVER IP>

rc-service sshd restart

## ------------------------------------------------------------------------
# [x] S9 - Diable IPv6
echo "Disable IPV6 ..."
cat << EOF > /etc/sysctl.d/99-disable-ipv6.conf
# Diable IPV6 (Comment the three following lines to get IPV6 back)
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv6.conf.eth0.disable_ipv6 = 1
EOF
#sysctl -p # to apply all the kernel parameters
sysctl -p /etc/sysctl.d/99-disable-ipv6.conf # to apply the modifications for the given file only

## ------------------------------------------------------------------------
# [x] S10 - Configure doas
## ------------------------------------------------------------------------
#echo "configure sudo and doas (required when using doas) ..."
## ------------------------------------------------------------------------

## ------------------------------------------------------------------------
## configure sudo/doas
#  !!!! Please to consider only one option

# ------------ no password required ------------
# for sudo --> echo '%wheel ALL=(ALL) NOPASSWD: ALL' > "/etc/sudoers.d/wheel"
#echo 'permit nopass :wheel' > "/etc/doas.d/wheel.conf"
#echo 'permit nopass keepenv root as root' >> "/etc/doas.d/wheel.conf"

# ------------ with required user password ------------
# for sudo --> echo '%wheel ALL=(ALL) ALL' > "/etc/sudoers.d/wheel"
echo 'permit persist :wheel' > "/etc/doas.d/wheel.conf"
echo 'permit persist keepenv root as root' >> "/etc/doas.d/wheel.conf"

## ------------------------------------------------------------------------
# [x] S11 - Install webdav with apache ...
# First step, create a password from PVE01 using the pass manager and put it in the file as follows.
WEBDAV_USERNAME=webdav
WEBDAV_PASSWORD=$(cat /root/secret_webdav.txt)
apk add  --no-cache apache2-webdav apache2-utils apache2-ssl 
mkdir -p /var/lib/dav 
chown apache:apache /var/lib/dav 
chmod 755 /var/lib/dav
htpasswd -cb /etc/apache2/webdav.password $WEBDAV_USERNAME $WEBDAV_PASSWORD

cat << EOF > /etc/apache2/conf.d/dav.conf
# Distributed authoring and versioning (WebDAV)
#
# Required modules: mod_alias, mod_auth_digest, mod_authn_core, mod_authn_file,
#                   mod_authz_core, mod_authz_user, mod_dav, mod_dav_fs,
#                   mod_setenvif
LoadModule auth_digest_module modules/mod_auth_digest.so
LoadModule dav_module modules/mod_dav.so
LoadModule dav_fs_module modules/mod_dav_fs.so

# The User/Group specified in httpd.conf needs to have write permissions
# on the directory where the DavLockDB is placed and on any directory where
# "Dav On" is specified.

DavLockDB /var/lib/dav/lockdb

Alias /webdav /var/lib/dav
<Location /webdav/>
    DAV on
    Options +Indexes
    AuthType Basic
    AuthName "webdav"
    AuthUserFile /etc/apache2/webdav.password
    Require valid-user
</Location>

<Directory /var/lib/dav/>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

# The following directives disable redirects on non-GET requests for
# a directory that does not include the trailing slash.  This fixes a
# problem with several clients that do not appropriately handle
# redirects for folders with DAV methods.
#
BrowserMatch "Microsoft Data Access Internet Publishing Provider" redirect-carefully
BrowserMatch "MS FrontPage" redirect-carefully
BrowserMatch "^WebDrive" redirect-carefully
BrowserMatch "^WebDAVFS/1.[01234]" redirect-carefully
BrowserMatch "^gnome-vfs/1.0" redirect-carefully
BrowserMatch "^XML Spy" redirect-carefully
BrowserMatch "^Dreamweaver-WebDAV-SCM1" redirect-carefully
BrowserMatch " Konqueror/4" redirect-carefully
EOF
chown root:apache /etc/apache2/webdav.password
chmod 640 /etc/apache2/webdav.password

# Create the is_mounted file.
# This file is used by client to test if the folder is weel mounted or not.
# This file will be accessible for read only (0400).
touch /var/lib/dav/is_mounted
chmod 400 /var/lib/dav/is_mounted

#htdigest -c /usr/user.passwd DAV-upload ${WEBDAV_USERNAME}
rc-update add apache2
rc-service apache2 start
ufw allow https

#https://docs.nextcloud.com/server/latest/user_manual/en/files/access_webdav.html#accessing-files-using-linux
#echo "In the client side:"
#echo "  - install davfs2 (sudo apt install davfs2 or apk add davfs2)"
#echo "  - create the mount directory: mkdir /media/webdav"
#echo "  - create the secrets file: echo '/media/webdav webdav <PASSWORD>' >> /etc/davfs2/secrets"
#echo "  - update the visibility of the secrets file: chmod 600 /etc/davfs2/secrets"
#echo "  - update the fstab file: echo 'https://WEBDAV_MACHINE_IP/uploads /media/webdav davfs user,rw,auto 0 0' >> /etc/fstab"
#mount -t davfs https://WEBDAV_MACHINE_IP/uploads /media/webdav

## ------------------------------------------------------------------------
# [x] S12 - Install and configure Rclone

echo "Install and configure Rclone ..."
apk update
apk --no-cache add rclone
# generate a password for rclone/config
rclone config
# configure the backup server, and protect the configuration with the generated password
at <<EOF > /etc/periodic/daily/rclone-sync
#!/bin/sh
/usr/bin/rclone sync -v --ask-password=false --ignore-size --create-empty-src-dirs --log-file /var/log/rclone.log /var/lib/dav pcloud:/SyncCloud/myServers/OracleCloud/shares/
EOFc
chmod a+x /etc/periodic/daily/rclone-sync
run-parts --test /etc/periodic/daily # to check


## ------------------------------------------------------------------------
# [x] S13 - configure CRON and create a daily system update script
echo "configure CRON and create a daily system update scripte ..."
rc-update add crond
rc-service crond start
cat << EOF > /etc/periodic/daily/package-update
#!/bin/sh
update_log_file=/var/log/system-update.log
echo "------------------------------------" >> \$update_log_file 2>&1
update_date_start=\$(date +'%m-%d-%Y--%H:%M:%S')
echo "### --> Start daily update at \${update_date_start}" >> \$update_log_file 2>&1
/sbin/apk update >> \$update_log_file 2>&1
/sbin/apk upgrade --no-cache --available >> \$update_log_file 2>&1
update_date_end=\$(date +'%m-%d-%Y--%H:%M:%S')
echo "### --> Update ended at \${update_date_end}" >> \$update_log_file 2>&1
EOF
chmod a+x /etc/periodic/daily/package-update
run-parts --test /etc/periodic/daily # to check

## ------------------------------------------------------------------------
# [x] Last step -  Cleaning the system and reboot
echo "Cleaning the system ..."
apk -v cache clean
apk -v cache purge
rm /var/cache/apk/*
rm -rf /root/secret*

reboot

## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
# Step X - Install filebroweser
##echo "Install filebroweser ..."
##
##apk add bash curl
##curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash
##addgroup -S filebrowser
##adduser -S -s /sbin/nologin -H -h /var/lib/filebrowser -G filebrowser filebrowser
##mkdir -p /var/lib/filebrowser/storage
##chown -Rc filebrowser:filebrowser /var/lib/filebrowser
##mkdir /etc/filebrowser

##cat <<EOF > /etc/filebrowser/.filebrowser.toml
##address  = "0.0.0.0"
##port 	 = 8080
##root 	 = "/var/lib/filebrowser/storage"
##database = "/var/lib/filebrowser/filebrowser.db"
##log 	 = "/var/log/filebrowser.log"
##EOF
##touch /var/log/filebrowser.log
##chown -c filebrowser:filebrowser /var/log/filebrowser.log
##
##cat <<EOF > /etc/init.d/filebrowser
###!/sbin/openrc-run
##depend() {
##	need net
##}
##command="/usr/local/bin/filebrowser"
##command_user="filebrowser:filebrowser"
##pidfile="/run/${RC_SVCNAME}.pid"
##command_background=true
##EOF
##
##chmod -c 755 /etc/init.d/filebrowser
##rc-service filebrowser start
###rc-service filebrowser stop.
##rc-update add filebrowser default


## ------------------------------------------------------------------------

## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
## ------------------------------------------------------------------------
# Step 3 - install and configure the NFS server
#apk add --no-cache nfs-utils 
#mkdir /storage
#nano /etc/exports
#cat <<EOF > /etc/exports
## extremely insecure
#/storage    *(rw,async,no_subtree_check,no_wdelay,crossmnt,no_root_squash,insecure_locks,sec=sys,anonuid=0,anongid=0)
#EOF
#rc-service nfs start
#rc-update add nfs
#rc-status # to check
#exportfs -afv
#reboot