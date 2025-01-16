#!/bin/bash
# /etc/init.d/subnodes_ap
# starts up access point interface, nginx for broadcasting a wireless network with captive portal

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

	case "$1" in
		start)
			echo "Starting $NAME access point on interfaces $PHY:$WLAN0..."

			# associate the access point interface to a physical devices
			nmcli con down CONNECTION_NAME
			# put iface into AP mode
			#iw phy $PHY interface add $WLAN0 type __ap

			# add access point iface to our bridge
			if [[ -x /sys/class/net/br0 ]]; then
				nmcli con add type bridge-slave ifname INTERFACE master br0
			fi

			# bring up access point iface wireless access point interface
			nmcli con up CONNECTION_NAME

			# start nginx
			service nginx start
			;;
		status)
		;;
		stop)

			nmcli con down CONNECTION_NAME

			# delete access point iface to our bridge
			if [[ -x /sys/class/net/br0 ]]; then
			#	brctl delif br0 $WLAN0
				nmcli con down br0
			fi

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
