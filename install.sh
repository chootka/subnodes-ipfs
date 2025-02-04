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

read -p "This script will install ipfs, nginx, set up a wireless access point and captive portal with dnsmasq, and provide the option of configuring a BATMAN-ADV mesh point with batctl. Make sure you have one (or two, if installing the additional mesh point) USB wifi radios connected to your Raspberry Pi before proceeding. Press any key to continue..."
echo ""
clear


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# CHECK REQUIRED RADIOS
# check that iw list does not fail with 'nl80211 not found'
echo -en "Checking that USB wifi radio is available for access point..."
readarray IW < <(iw dev | awk '$1~"phy#"{PHY=$1}; $1=="Interface" && $2~"wlan"{WLAN=$2; sub(/#/, "", PHY); print PHY " " WLAN}')
if [[ -z $IW ]] ; then
	echo -en "[FAIL]\n"
	echo "Warning! Wireless adapter not found! Please plug in a wireless radio after installation completes and before reboot."
	echo "Installation process will proceed in 5 seconds..."
	sleep 5
else
	echo -en "[OK]\n"
fi

# now check that iw list finds a radio other than wlan0 if mesh point option was set to 'y' in config file
case $DO_SET_MESH in
	[Yy]* )
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
;;
esac


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# SOFTWARE INSTALL
#

# update the packages
echo -en "Updating apt and installing iw, dnsutils, nginx, batctl, tar, wget, bridge-utils"
apt update && apt install -y iw dnsutils nginx batctl tar wget bridge-utils
# Change the directory owner and group
chown www-data:www-data /var/www
# allow the group to write to the directory
chmod 775 /var/www
# Add the user to the www-data group
usermod -a -G www-data $USERNAME
systemctl start nginx

chgrp www-data /var/www/html
chown www-data /var/www/html
chmod 775 /var/www/html

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
# Check if we are configuring a mesh node

clear
echo -en "Checking whether to configure mesh point or not..."

case $DO_SET_MESH in
	[Yy]* )
		clear
		echo -en "Configuring Raspberry Pi as a BATMAN-ADV mesh point..."
		echo -en "Enabling the batman-adv kernel module..."
		# add the batman-adv module to be started on boot
		sed -i '$a batman-adv' /etc/modules
		modprobe batman-adv;

		# pass the selected mesh ssid into mesh startup script
		sed -i "s/MTU/$MTU/" scripts/subnodes_mesh.sh
		sed -i "s/SSID/$MESH_SSID/" scripts/subnodes_mesh.sh
		sed -i "s/CELL_ID/$CELL_ID/" scripts/subnodes_mesh.sh
		sed -i "s/CHAN/$MESH_CHANNEL/" scripts/subnodes_mesh.sh
		sed -i "s/GW_MODE/$GW_MODE/" scripts/subnodes_mesh.sh
		#sed -i "s/GW_SEL_CLASS/$GW_SEL_CLASS/" scripts/subnodes_mesh.sh
		#sed -i "s/GW_BANDWIDTH/$GW_BANDWIDTH/" scripts/subnodes_mesh.sh
		#sed -i "s/GW_IP/$GW_IP/" scripts/subnodes_mesh.sh

		nmcli con delete br0
		nmcli con add type bridge ifname br0 con-name br0 autoconnect yes
		nmcli con modify br0 ipv4.method shared ipv4.address $BRIDGE_IP
		nmcli con modify br0 bridge.stp no
		nmcli con add type bridge-slave ifname bat0 master br0
		nmcli con add type bridge-slave ifname $INTERFACE master br0
		nmcli con up br0

		# COPY OVER START UP SCRIPTS
		echo ""
		echo "Adding startup scripts to init.d..."
		sed -i "s/INTERFACE/$INTERFACE/" scripts/subnodes_ap.sh
                sed -i "s/CONNECTION_NAME/$CONNECTION_NAME/" scripts/subnodes_ap.sh
		cp scripts/subnodes_ap.sh /etc/init.d/subnodes_ap
		chmod 755 /etc/init.d/subnodes_ap
		update-rc.d subnodes_ap defaults
		cp scripts/subnodes_mesh.sh /etc/init.d/subnodes_mesh
		chmod 755 /etc/init.d/subnodes_mesh
		update-rc.d subnodes_mesh defaults
	;;


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# Access Point only
#

	[Nn]* )
	# if no mesh point is created, set up network manager to work without a bridge
		clear

		nmcli con delete $CONNECTION_NAME
		nmcli con add type wifi ifname $INTERFACE mode ap con-name $CONNECTION_NAME ssid $AP_SSID autoconnect yes
		nmcli con modify $CONNECTION_NAME 802-11-wireless.band bg 802-11-wireless.channel $AP_CHAN
		nmcli con modify $CONNECTION_NAME ipv4.method shared ipv4.address $AP_IP
		#nmcli con modify $CONNECTION_NAME wifi-sec.key-mgmt wpa-psk wifi-sec.psk "mypassword"
		nmcli con up $CONNECTION_NAME

		# COPY OVER START UP SCRIPTS
		echo ""
		echo "Adding startup scripts to init.d..."
		sed -i "s/INTERFACE/$INTERFACE/" scripts/subnodes_ap.sh
                sed -i "s/CONNECTION_NAME/$CONNECTION_NAME/" scripts/subnodes_ap.sh
		cp scripts/subnodes_ap.sh /etc/init.d/subnodes_ap
		chmod 755 /etc/init.d/subnodes_ap
		update-rc.d subnodes_ap defaults
	;;
esac

# NEED TO SET managed=true in /etc/NetworkManager/NetworkManager.conf


# # # # # # # # # # # # # # # # # # # # # # # # # # #
# IPFS CONFIG
#

# using IPFS?
case $DO_SET_IPFS in
        [Yy]* )
		# install ipfs kubo
		cd /home/$USERNAME
		wget https://sourceforge.net/projects/ipfs-kubo.mirror/files/v0.28.0/$KUBO
		tar -xvzf $KUBO
		rm $KUBO
		cd kubo && ./install.sh
		sudo -u $USERNAME ipfs init
		sed -i -e '$i \ipfs daemon &\n' /etc/rc.local
		cd /home/$USERNAME/subnodes-ipfs
		echo pwd

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
	;;
esac

# TO-DO: Give ppl the choice of which site to host on IPFS

read -p "Do you wish to reboot now? [N] " yn
	case $yn in
		[Yy]* )
			reboot;;
		[Nn]* ) exit 0;;
	esac
