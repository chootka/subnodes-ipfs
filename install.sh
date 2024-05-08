#! /bin/bash
#
# Raspberry Pi network configuration / AP, MESH install script
# Author: Sarah Grant
# Contributors: Mark Hansen, Matthias Strubel, Danja Vasiliev
# took guidance from a script by Paul Miller : https://dl.dropboxusercontent.com/u/1663660/scripts/install-rtl8188cus.sh
# Updated 20 April 2024
#
# TO-DO
# - allow a selection of radio drivers
# - fix addressing to avoid collisions below w/avahi

USERNAME=$1
KUBO="kubo_v0.28.0_linux-arm64.tar.gz"

# # # # # # # # # # # # # # # # # # # # # # # # # # #
# first find out if this is RPi3 or not, based on revision code
# reference: http://www.raspberrypi-spy.co.uk/2012/09/checking-your-raspberry-pi-board-version/
REV="$(cat /proc/cpuinfo | grep 'Revision' | awk '{print $3}')"


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# READ configuration file
. ./subnodes.config


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# CHECK USER PRIVILEGES
(( `id -u` )) && echo "This script must be ran with root privileges, try prefixing with sudo. i.e sudo $0" && exit 1


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# BEGIN INSTALLATION PROCESS
#

clear
echo "Installing Subnodes..."
echo ""

read -p "This script will install ipfs, nginx, set up a wireless access point and captive portal with hostapd and dnsmasq. Make sure you have an additional USB wifi radios connected to your Raspberry Pi before proceeding. Press any key to continue..."
echo ""
clear


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# CHECK REQUIRED RADIOS
# check that iw list does not fail with 'nl80211 not found'
echo -en "Checking that USB wifi radio is available for mesh point..."
readarray IW < <(iw dev | awk '$1~"phy#"{PHY=$1}; $1=="Interface" && $2!="wlan0"{WLAN=$2; sub(/#/, "", PHY); print PHY " " WLAN}')

if [[ -z $IW ]] ; then
	echo -en "[FAIL]\n"		
 	echo "Warning! Second wireless adapter not found! Please plug in an addition wireless radio after installation completes and before reboot."
	echo "Installation process will proceed in 5 seconds..."
	sleep 5
else
	echo -en "[OK]\n"
fi


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# SOFTWARE INSTALL
#

# update the packages
echo -en "Updating apt and installing iw, dnsutils, nginx, tar, wget"
apt update && apt install -y iw dnsutils nginx tar wget
# Change the directory owner and group
chown www-data:www-data /var/www
# allow the group to write to the directory
chmod 775 /var/www
# Add the user to the www-data group
usermod -a -G www-data $USERNAME
systemctl start nginx

# install ipfs-rpi repo
cd /home/$USERNAME
wget https://sourceforge.net/projects/ipfs-kubo.mirror/files/v0.28.0/$KUBO
tar -xvzf $KUBO
rm $KUBO
cd kubo && ./install.sh
sudo -u $USERNAME ipfs init
sed -i -e '$i \ipfs daemon &\n' /etc/rc.local
cd /home/$USERNAME/subnodes-ipfs
echo pwd

echo -en "Loading the subnodes configuration file..."

# Check if configuration exists, ask for overwriting
if [ -e /etc/subnodes.config ] ; then
        read -p "Older config file found! Overwrite? (y/n) [N]" -e $q
        if [ "$q" == "y" ] ; then
                echo "...overwriting"
                copy_ok="yes"
        else
                echo "...not overwriting. Re-reading found configuration file..."
                . /etc/subnodes.config
        fi
else
        copy_ok="yes"
fi

# copy config file to /etc
[ "$copy_ok" == "yes" ] && cp subnodes.config /etc


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# Configure the access point and captive portal
#

clear
echo -en "Configuring Access Point..."

# install required packages
echo -en "Installing bridge-utils, hostapd and dnsmasq..."
apt install -y bridge-utils hostapd dnsmasq
echo -en "[OK]\n"

# backup the existing interfaces file
echo -en "Creating backup of network interfaces configuration file..."
cp /etc/network/interfaces /etc/network/interfaces.bak

rc=$?
if [[ $rc != 0 ]] ; then
		echo -en "[FAIL]\n"
	exit $rc
else
	echo -en "[OK]\n"
fi

# create hostapd init file
echo -en "Creating default hostapd file..."
cat <<EOF > /etc/default/hostapd
DAEMON_CONF="/etc/hostapd/hostapd.conf"
EOF
	rc=$?
	if [[ $rc != 0 ]] ; then
			echo -en "[FAIL]\n"
		echo ""
		exit $rc
	else
		echo -en "[OK]\n"
	fi


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# Access Point only
#

# configure dnsmasq
echo -en "Creating dnsmasq configuration file..."
cat <<EOF > /etc/dnsmasq.conf
# Captive Portal logic (redirects traffic coming in on br0 to our web server)
interface=wlan1
address=/#/$AP_IP

# DHCP server
dhcp-range=$AP_DHCP_START,$AP_DHCP_END,$DHCP_NETMASK,$DHCP_LEASE
EOF
	rc=$?
	if [[ $rc != 0 ]] ; then
		echo -en "[FAIL]\n"
		echo ""
		exit $rc
	else
		echo -en "[OK]\n"
	fi

# create new /etc/network/interfaces
echo -en "Creating new network interfaces with your settings..."
cat <<EOF > /etc/network/interfaces
auto lo
iface lo inet loopback

allow-hotplug eth0
auto eth0
iface eth0 inet dhcp

auto wlan0
iface wlan0 inet dhcp

auto wlan1
iface wlan1 inet static
address $AP_IP
netmask $AP_NETMASK

iface default inet dhcp
EOF
	rc=$?
	if [[ $rc != 0 ]] ; then
		    echo -en "[FAIL]\n"
			echo ""
		exit $rc
	else
		echo -en "[OK]\n"
	fi

# create hostapd configuration with user's settings
echo -en "Creating hostapd.conf file..."
cat <<EOF > /etc/hostapd/hostapd.conf
interface=wlan1
driver=$RADIO_DRIVER
country_code=$AP_COUNTRY
ctrl_interface=/var/run/hostapd
ctrl_interface_group=0
ssid=$AP_SSID
hw_mode=g
channel=$AP_CHAN
auth_algs=1
wpa=0
ap_isolate=1
macaddr_acl=0
wmm_enabled=1
ieee80211n=1
EOF
	rc=$?
	if [[ $rc != 0 ]] ; then
		echo -en "[FAIL]\n"
		exit $rc
	else
		echo -en "[OK]\n"
	fi

# COPY OVER START UP SCRIPTS
echo ""
echo "Adding startup scripts to init.d..."
cp scripts/subnodes_ap.sh /etc/init.d/subnodes_ap
chmod 755 /etc/init.d/subnodes_ap
update-rc.d subnodes_ap defaults


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# IPFS CONFIG
#

case $BOOTSTRAP_NODE in
	[Yy]* )
		sudo -u $USERNAME echo -e "/key/swarm/psk/1.0.0/\n/base16/\n`tr -dc 'a-f0-9' < /dev/urandom | head -c64`" > sudo -u $USERNAME $HOME/.ipfs/swarm.key
		echo -en "! You must copy this key to ~/.ipfs/swarm.key on all client nodes:"
		sudo -u $USERNAME cat $HOME/.ipfs/swarm.key

		BOOTSTRAP_IP=$(hostname -I)
		echo -en "Copy this IP address to share with client nodes: $BOOTSTRAP_IP"

		BOOTSTRAP_PEER_ID=$(ipfs config show | grep "PeerID" | cut -d'"' -f 4)
		echo -en "Copy this peer ID to share with client nodes: $BOOTSTRAP_PEER_ID"
		read -p "Did you copy everything? Hit <enter> to keep going..."

		sudo -u $USERNAME ipfs bootstrap rm --all
		sudo -u $USERNAME ipfs bootstrap add /ip4/$BOOTSTRAP_IP/tcp/4001/ipfs/$BOOTSTRAP_PEER_ID
	;;
	[Nn]* )
		echo "Adding swarm.key to .ipfs..."
                cp scripts/swarm.key /home/$USERNAME/.ipfs/swarm.key
		chown $USERNAME:$USERNAME /home/$USERNAME/.ipfs/swarm.key
                chmod 644 /home/$USERNAME/.ipfs/swarm.key
		# Check if a swarm.key exists, ask for overwriting
		#if [ -e sudo -u $USERNAME $HOME/.ipfs/swarm.key ] ; then
		#        read -p "swarm.key already exists! Overwrite? (y/n) [N]" -e $q
		#        if [ "$q" == "y" ] ; then
		#                echo "...overwriting"
		#                overwrite_sk="yes"
		#        else
		#                echo "...not overwriting."
		#        fi
		#else
		#        overwrite_sk="yes"
		#fi

		# copy swarm.key from config to .ipfs
		# [ "$overwrite_sk" == "yes" ] && sudo -u $USERNAME echo $SWARM_KEY > sudo -u $USERNAME $HOME/.ipfs/swarm.key

		sudo -u $USERNAME ipfs bootstrap rm --all
		sudo -u $USERNAME ipfs bootstrap add /ip4/$BOOTSTRAP_IP/tcp/4001/ipfs/$BOOTSTRAP_PEER_ID
	;;
esac

export LIBP2P_FORCE_PNET=1
sed -i -e "\$i sudo -u $USERNAME ipfs daemon &\n" /etc/rc.local

# TO-DO: Give ppl the choice of which site to host on IPFS

chgrp www-data /var/www/html
chown www-data /var/www/html
chmod 775 /var/www/html


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# enable services
#

clear
update-rc.d dnsmasq enable
update-rc.d hostapd remove
systemctl unmask hostapd
systemctl enable hostapd

read -p "Do you wish to reboot now? [N] " yn
	case $yn in
		[Yy]* )
			reboot;;
		[Nn]* ) exit 0;;
	esac
