#!/bin/bash
# /etc/init.d/subnodes_ap
# starts up node.js app, access point interface, hostapd, and dnsmasq for broadcasting a wireless network with captive portal

### BEGIN INIT INFO
# Provides:          subnodes_ap
# Required-Start:    dbus
# Required-Stop:     dbus
# Should-Start:	     $syslog
# Should-Stop:       $syslog
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Subnodes Access Point
# Description:       Subnodes Access Point script
### END INIT INFO

NAME=subnodes_ap
DESC="Brings up wireless access point for connecting to web server running on the device."
DAEMON_PATH="/home/pi/subnodes"
PIDFILE=/var/run/$NAME.pid

# get first PHY WLAN pair
readarray IW < <(iw dev | awk '$1~"phy#"{PHY=$1}; $1=="Interface" && $2!="wlan0"{WLAN=$2; sub(/#/, "", PHY); print PHY " " WLAN}')

IW1=( ${IW[0]} )

PHY=${IW1[0]}
WLAN1=${IW1[1]}

echo $PHY $WLAN1 > /tmp/ap.log

	case "$1" in
		start)
			echo "Starting $NAME access point on interfaces $PHY:$WLAN1..."

			# associate the access point interface to a physical devices
			ifconfig $WLAN1 down
			# put iface into AP mode
			iw phy $PHY interface add $WLAN1 type __ap

			# add access point iface to our bridge
			if [[ -x /sys/class/net/br0 ]]; then
				brctl addif br0 $WLAN1
			fi

			# bring up access point iface wireless access point interface
			ifconfig $WLAN1 up

			# start the hostapd and dnsmasq services
			service dnsmasq start
			service hostapd restart
			service nginx start
			;;
		status)
		;;
		stop)

			ifconfig $WLAN1 down

			# delete access point iface to our bridge
			if [[ -x /sys/class/net/br0 ]]; then
				brctl delif br0 $WLAN1
			fi

			service hostapd stop
            		service dnsmasq stop
            		service nginx stop
		;;

		restart)
			$0 stop
			$0 start
		;;

*)
		echo "Usage: $0 {status|start|stop|restart}"
		exit 1
esac
