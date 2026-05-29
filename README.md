# Lazycast (for Debian)

Lazycast is a simple wifi display receiver for Linux. It supports Windows 11 sources and Miracast sources. For Windows 11, the Miracast over Infrastructure (**MICE**) feature is also supported, which may provide better user experiences. For video playback from Android sources, modify the ``player_select`` option in ``d2.py``.

# DietPi / Debian

This section covers installation on **DietPi** or **Debian Trixie** on standard x86/ARM hardware.

The in-house players (`player.bin`, `h264.bin`) require GPU libraries specific to the Broadcom VideoCore chip and cannot be compiled on standard hardware. VLC or GStreamer is used instead. `player_select` is automatically set to `0` (VLC) at runtime — no code change needed.

Do **not** run `make`.

## Installation

Clone the repository:
```bash
git clone https://github.com/hawkinslabdev/lazycast
cd lazycast
```

Install required packages:
```bash
sudo apt install python3 python3-evdev wpasupplicant busybox-static net-tools mpv
```

- `busybox-static` — the plain `busybox` package omits the `udhcpd` applet that `all.sh` uses as a DHCP server
- `net-tools` — provides `ifconfig`, called by `all.sh` to assign an IP to the P2P interface; not installed by default on Trixie
- `mpv` — video player with `--vo=drm` support for headless HDMI output
- `python3` — required for `p2p_monitor.py`, which `all.sh` uses to handle Wi-Fi Direct negotiation

## Wi-Fi adapter requirement

The wireless adapter must support **Wi-Fi Direct (P2P)**. Most Intel Wi-Fi adapters (AX200, AX210, Wi-Fi 6/6E) support P2P. Many budget USB adapters do not. Verify support with:
```bash
iw list | grep -A10 "Supported interface modes" | grep P2P
```
If `P2P-GO` and `P2P-client` appear, the adapter is compatible.

## wpa_supplicant

lazycast drives Wi-Fi P2P entirely through `wpa_cli`. A standalone `wpa_supplicant` instance must be running and managing the wireless interface.

**DietPi:** `wpa_supplicant` is installed but not running by default. Set it up once:

1. Ensure `/etc/wpa_supplicant/wpa_supplicant.conf` contains these lines. If `update_config=` is missing the value, fix it:
```
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=1
```
```
sudo sed -i 's/^update_config=$/update_config=1/' /etc/wpa_supplicant/wpa_supplicant.conf
```

2. The `wpa_supplicant@wlan0` service expects a file named `wpa_supplicant-wlan0.conf`. Create a symlink:
```
sudo ln -s /etc/wpa_supplicant/wpa_supplicant.conf /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
```

3. Enable and start:
```
sudo systemctl enable wpa_supplicant@wlan0
sudo systemctl start wpa_supplicant@wlan0
```

4. Verify — output should list `p2p-dev-wlan0` and `wlan0`:
```
sudo wpa_cli interface
```

<details>
<summary><strong>Debian Trixie desktop only — expand if <code>systemctl is-active NetworkManager</code> returns <code>active</code></strong></summary>

NetworkManager keeps its own private wpa_supplicant instance that `wpa_cli` cannot reach. Unmanage the Wi-Fi adapter:
```
sudo mkdir -p /etc/NetworkManager/conf.d
sudo tee /etc/NetworkManager/conf.d/unmanaged.conf <<EOF
[keyfile]
unmanaged-devices=interface-name:wlan0
EOF
```
Restart NetworkManager, then start a standalone wpa_supplicant:
```
sudo systemctl restart NetworkManager
sudo wpa_supplicant -Dnl80211 -iwlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf -u &
```
Ensure `/etc/wpa_supplicant/wpa_supplicant.conf` contains:
```
ctrl_interface=DIR=/run/wpa_supplicant GROUP=netdev
update_config=1
```
</details>

## Video output

`d2.py` defaults to `mpv` with DRM/KMS output — no desktop environment required:
```python
os.system('mpv --no-terminal --vo=drm --drm-connector=HDMI-A-1 --fs rtp://0.0.0.0:1028 > /tmp/mpv.log 2>&1 &')
```

**Headless with HDMI output (no desktop environment):** Uses `mpv --vo=drm` which properly acquires DRM master, hides the framebuffer console, scales to display resolution, and handles audio. Install with `sudo apt install mpv`. If the connector name differs from `HDMI-A-1`, find it with `ls /sys/class/drm/ | grep connected` and update the `--drm-connector` value in `d2.py`.

**Desktop (X11):** In `d2.py` inside `launchplayer`, change `if True:` to `if False:`. This switches to VLC. Install VLC (`sudo apt install vlc`) and ensure the `DISPLAY` environment variable is set when `all.sh` runs. If starting via systemd, add `Environment=DISPLAY=:0` to the service file.

**Desktop (Wayland):** Same as X11 but add `--vout=wayland` to the VLC command.

For audio on headless systems, extend the GStreamer pipeline or use the VLC fallback with `--aout=alsa`.

## Start on boot (systemd)

A `lazycast.service` file is included in the repository. Edit the paths and add ordering dependencies before installing:
```ini
[Unit]
Description=lazycast server
After=network-online.target wpa_supplicant.service
Wants=network-online.target

[Service]
ExecStart=/home/<user>/lazycast/all.sh
WorkingDirectory=/home/<user>/lazycast
# If running under a desktop session, uncomment and set:
# Environment=DISPLAY=:0

[Install]
WantedBy=multi-user.target
```
Install and enable:
```bash
sudo cp lazycast.service /etc/systemd/system/lazycast.service
sudo systemctl daemon-reload
sudo systemctl enable lazycast
```

## MICE on Debian Trixie

`mice.sh` auto-detects whether to stop `dhcpcd` or use a standalone `wpa_supplicant` restart, depending on what is active. For Debian Trixie, ensure `wlan0` is unmanaged by NetworkManager before running MICE (see wpa_supplicant section above).

MICE also requires additional Python packages:
```bash
sudo apt install python3-dbus python3-gi
```

# Usage
Run `./all.sh` to start lazycast receiver. Wait until the "The display is ready" message. The name of the display will appear after this message. Then, search for this name on the source device you want to cast. The default PIN number is ``31415926``. 

It is recommended to stop casting by the controls on the source (e.g., the PC) side.

# Tips
Set the resolution on the source side. lazycast advertises all possible resolutions regardless of the current rendering resolution. Change the resolution on the source to match the actual display resolution.

Modify parameters in the "settings" section in ``d2.py`` to change the sound output port and preferred player.

The maximum resolutions supported are 1920x1080p60 and 1920x1200p30. If latency is high at 1920x1080p60, reduce to 1920x1080p50.

To change the default PIN number, replace the string ``31415926`` in ``all.sh`` with another 8-digit number.

You can hide the cursor by using ``unclutter -idle 3``.

After the receiver connects to the source, it has an IP address of ``192.168.173.1`` and this connection can be reused for other purposes like SSH. Since both devices are under the same subnet, take precautions to prevent unauthorized access by anyone who knows the PIN number.

**It is very important that no background WiFi scanning occurs during casting.** Disable any network manager plugins or tray applets that trigger periodic scans on the wireless interface used for casting. Verify no scanning is occurring by running ``iw event`` in a second terminal — no events should appear during casting. If the wireless interface is not connected to any network, the OS may trigger periodic scanning automatically; stop this with ``sudo ifconfig wlan0 down`` if the interface is not needed for regular internet access.

To redirect mouse and keyboard inputs, first install evdev (``sudo apt install python3-evdev``) and then set ``enable_mouse_keyboard`` to ``1`` in ``d2.py``. You also need to allow mouse and keyboard inputs on the source device.

# Known issues
lazycast tries to remember the pairing credentials so that entering the PIN is only needed once for each device. However, this feature may not work reliably and re-pairing may be needed after every reboot. Try clearing the 'lazycast' information on the source device before re-pairing if you run into pairing problems.

Latency: Limited by the RTP player implementation. In VLC, latency can be reduced from 1200 to 300ms by lowering the network cache value (``--network-caching=300``).

Due to the overcrowded nature of the wifi spectrum and the use of unreliable RTP transmission, you may experience video glitching or audio stuttering. Interference from other devices may cause disconnections.

Devices may not fully support backchannel control and some keystrokes/clicks will behave differently.

HDCP (content protection) is not supported.

<!-- Some Windows 11 devices seem to disconnect shortly after a connection is established. You can try using ``win11debug.sh`` instead of ``all.sh`` and see if it helps. -->

# Start on boot

See the **Start on boot (systemd)** section under [DietPi / Debian](#dietpi--debian) above.

# Miracast over Infrastructure

For Windows 11 sources, Miracast over Infrastructure (MICE) is a feature that allows transmission of screen data over Ethernet or secure wifi networks. The spec is available [here](https://winprotocoldoc.blob.core.windows.net/productionwindowsarchives/MS-MICE/%5bMS-MICE%5d.pdf). Compared to wifi p2p, it allows stabler connection and lower latency. MICE relies on Ethernet or secure wifi for data, but still requires a wifi p2p device to broadcast beacon and probe response frames during device discovery. It is possible to run the beacon and the receiver on two separate machines — set the ``hostname`` variable in ``mice.py`` to the hostname of the machine running ``project.py``.

Currently tested with a Windows 11 PC and a receiver (with manually assigned IPs) connected via Ethernet. Ports used include but are not limited to UDP 53 (DNS), UDP 5353 (mDNS), TCP 7236 and TCP 7250. Encryption is not implemented — use only over trusted networks. IPv6 networks are supported but only IPv4 is implemented.

## Preparation
Install avahi-utils:
```bash
sudo apt install avahi-utils
```
Make sure the Windows 11 PC is on the same network as the receiver. Verify by pinging the receiver from the PC.

For Debian/DietPi: see the **MICE on Debian Trixie** section above for wpa_supplicant setup and additional packages. Run ``resetwpa.sh`` or reboot to restore normal WiFi operation after MICE.

## Usage
Make sure no p2p interface has already been created and ``all.sh`` is not running. Then run:
```bash
./mice.sh
```

Use the "Connect" tab in Windows 11 and connect to the hostname of the receiver. Windows may try the traditional method first and ask for a PIN — cancel and try again. With MICE, no PIN prompt should appear.

Windows 11 assigns the display name based on the connected monitor. If the monitor is detected, the display name changes to the monitor name; otherwise it shows "Device". After disconnection it reverts to the receiver's hostname.

To run MICE and wifi p2p simultaneously, set ``concurrent`` to ``1`` in ``newmice.py`` and use only ``mice.sh``. If mDNS is not working with multiple IPs, manually set the ``ipstr`` variable in ``newmice.py`` to the target IP.  

# License

This project is licensed under the **GPL 3.0** license. See [LICENSE](https://github.com/homeworkc/lazycast/LICENSE) for details.