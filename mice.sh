#!/bin/bash
# Stop dhcpcd if it is managing wpa_supplicant (Raspberry Pi OS)
DHCPCD_WAS_ACTIVE=0
if systemctl is-active --quiet dhcpcd 2>/dev/null; then
    DHCPCD_WAS_ACTIVE=1
    sudo systemctl stop dhcpcd
fi

sudo systemctl stop wpa_supplicant 2>/dev/null || true
sudo pkill wpa_supplicant 2>/dev/null || true
sudo wpa_supplicant -Dnl80211 -iwlan0 -u -c/etc/wpa_supplicant/wpa_supplicant.conf &
sleep 1

# On Raspberry Pi OS, restart dhcpcd so Ethernet/network is available for MICE
if [ "$DHCPCD_WAS_ACTIVE" = "1" ]; then
    sudo systemctl start dhcpcd
fi

LD_LIBRARY_PATH=/opt/vc/lib
export LD_LIBRARY_PATH
./newmice.py
