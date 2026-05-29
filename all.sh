#!/bin/bash
#################################################################################
# Run script for lazycast
# Licensed under GNU General Public License v3.0 GPL-3 (in short)
#
#   You may copy, distribute and modify the software as long as you track
#   changes/dates in source files. Any modifications to our software
#   including (via compiler) GPL-licensed code must also be made available
#   under the GPL along with build & install instructions.
#
#################################################################################
managefrequency=0
LD_LIBRARY_PATH=/opt/vc/lib
export LD_LIBRARY_PATH

info()  { echo "[lazycast] $*"; }
ok()    { echo "[lazycast] OK: $*"; }
warn()  { echo "[lazycast] WARN: $*"; }

while :
do
	# Kill any leftover P2P monitor from a previous session
	sudo pkill -f "python3 ./p2p_monitor.py" 2>/dev/null || true

	p2pdevinterface=$(sudo wpa_cli interface | grep -E "p2p-dev" | tail -1)
	wlaninterface=$(echo $p2pdevinterface | cut -c1-8 --complement)

	if [ -z "$p2pdevinterface" ]; then
		warn "No P2P device interface found. Is wpa_supplicant running? (sudo systemctl start wpa_supplicant@wlan0)"
		sleep 5
		continue
	fi

	ain="$(sudo wpa_cli interface)"

	# Remove stale P2P group if one exists from a previous run
	if [ `echo "${ain}" | grep -c "p2p-wl"` -gt 0 ]
	then
		stale=$(echo "${ain}" | grep "p2p-wl" | grep -v "interface")
		info "Removing stale P2P group: $stale"
		sudo wpa_cli -i"$stale" p2p_group_remove "$stale" 2>/dev/null || true
		sleep 3
		ain="$(sudo wpa_cli interface)"
	fi

	if [ `echo "${ain}" | grep -c "p2p-wl"` -lt 1 ]
	then
		info "Starting Wi-Fi Direct discovery on $p2pdevinterface ..."

		sudo wpa_cli -i$p2pdevinterface p2p_find type=progressive     > /dev/null
		sudo wpa_cli -i$p2pdevinterface set device_name "$(uname -n)" > /dev/null
		sudo wpa_cli -i$p2pdevinterface set device_type 7-0050F204-1  > /dev/null
		sudo wpa_cli -i$p2pdevinterface set p2p_go_ht40 1             > /dev/null
		sudo wpa_cli -i$p2pdevinterface wfd_subelem_set 0 000600111c44012c > /dev/null
		sudo wpa_cli -i$p2pdevinterface wfd_subelem_set 1 0006000000000000 > /dev/null
		sudo wpa_cli -i$p2pdevinterface wfd_subelem_set 6 000700000000000000 > /dev/null

		perentry="$(sudo wpa_cli -i$p2pdevinterface list_networks | grep "\[DISABLED\]\[P2P-PERSISTENT\]" | tail -1)"
		if [ `echo "${perentry}" | grep -c "P2P-PERSISTENT"` -gt 0 ]
		then
			networkid=${perentry%%D*}
			perstr="=${networkid}"
			info "Found persistent P2P network (id=$networkid), will reuse credentials"
		else
			perstr=""
		fi

		if [ "$managefrequency" != "0" ]
		then
			wlanfreq=$(sudo wpa_cli -i$wlaninterface status | grep "freq")
			if [ "$wlanfreq" != "" ]
			then
				info "Matching P2P frequency to $wlaninterface: $wlanfreq"
			fi
		fi

		echo "$(date) starting p2p_monitor on $p2pdevinterface" >> /tmp/lazycast_action.log
		sudo python3 ./p2p_monitor.py $p2pdevinterface &
		WPA_ACTION_PID=$!

		info "Waiting for source device to initiate connection..."
		info "(On the source: open cast/display settings and select '$(uname -n)')"

		while [ `echo "${ain}" | grep -c "p2p-wl"` -lt 1 ]
		do
			while [ `echo "${ain}" | grep -c "p2p-wl"` -lt 1 ]
			do
				sleep 2
				ain="$(sudo wpa_cli interface)"
			done
			sleep 5
			ain="$(sudo wpa_cli interface)"
		done

		sudo kill $WPA_ACTION_PID 2>/dev/null || true
		ok "P2P group formed"
	fi

	ain="$(sudo wpa_cli interface)"
	p2pinterface=$(echo "${ain}" | grep "p2p-wl" | grep -v "interface")

	info "P2P interface: $p2pinterface — configuring network ..."

	sudo wpa_cli -i$p2pdevinterface p2p_find type=progressive > /dev/null
	sudo pkill -f "busybox udhcpd" 2>/dev/null || true
	sudo ifconfig $p2pinterface 192.168.173.1

	printf "start\t192.168.173.80\n"  > udhcpd.conf
	printf "end\t192.168.173.80\n"   >> udhcpd.conf
	printf "interface\t$p2pinterface\n" >> udhcpd.conf
	printf "option subnet 255.255.255.0\n" >> udhcpd.conf
	printf "option lease 10000\n"    >> udhcpd.conf

	sleep 3
	sudo busybox udhcpd ./udhcpd.conf

	ok "Display ready — device name: $(uname -n)"
	info "Logs: /tmp/lazycast.log  /tmp/lazycast_action.log  /tmp/mpv.log"

	while :
	do
		sudo wpa_cli -i$p2pinterface wps_pbc > /dev/null
		info "Waiting for WPS/PBC handshake from source ..."
		./d2.py 2>&1 | tee -a /tmp/lazycast.log

		if [ `sudo wpa_cli interface | grep -c "p2p-wl"` == 0 ]
		then
			info "P2P group removed — restarting discovery"
			break
		fi

		if [ "$managefrequency" != "0" ]
		then
			wlanfreq=$(sudo wpa_cli -i$wlaninterface status | grep "freq")
			p2pfreq=$(sudo wpa_cli -i$p2pinterface status | grep "freq")
			if [ "$wlanfreq" != "" ] && [ "$wlanfreq" != "$p2pfreq" ]
			then
				warn "Display disconnected: $wlaninterface moved from $p2pfreq to $wlanfreq"
				warn "To stop WLAN roaming: sudo killall -STOP NetworkManager"
				warn "Re-enable roaming:    sudo killall -CONT NetworkManager"
				sudo wpa_cli -i$p2pinterface p2p_group_remove $p2pinterface
				while :
				do
					if [ `sudo wpa_cli interface | grep -c "p2p-wl"` == 0 ]
					then
						break
					fi
				done
				break
			fi
		fi

	done
done
