#!/usr/bin/env python3
"""
Monitor wpa_supplicant P2P events and respond to GO-NEG-REQUEST.
Communicates directly via the UNIX DGRAM control socket.
"""
import socket
import os
import sys
import time

LOG = '/tmp/lazycast_action.log'

def log(msg):
    with open(LOG, 'a') as f:
        f.write(f'{time.strftime("%c")} {msg}\n')

def ctrl_send(sock, server_path, cmd):
    sock.sendto(cmd.encode(), server_path)
    try:
        resp = sock.recv(4096).decode().strip()
    except Exception as e:
        resp = f'ERROR:{e}'
    return resp

def main():
    iface = sys.argv[1] if len(sys.argv) > 1 else 'p2p-dev-wlan0'
    server_path = f'/run/wpa_supplicant/{iface}'
    client_path = f'/tmp/wpa_p2pmon_{os.getpid()}'

    log(f'p2p_monitor starting on {iface}')

    if not os.path.exists(server_path):
        log(f'ERROR: {server_path} not found')
        sys.exit(1)

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    sock.bind(client_path)
    sock.settimeout(5)

    try:
        resp = ctrl_send(sock, server_path, 'ATTACH')
        log(f'ATTACH: {resp}')
        if 'OK' not in resp:
            log('ATTACH failed, exiting')
            sys.exit(1)

        sock.settimeout(None)  # block indefinitely waiting for events

        while True:
            try:
                data = sock.recv(4096).decode().strip()
            except Exception as e:
                log(f'recv error: {e}')
                break

            log(f'EV: {data}')

            if 'P2P-GO-NEG-REQUEST' in data:
                # Format: <3>P2P-GO-NEG-REQUEST <mac> dev_passwd_id=N go_intent=N
                parts = data.split()
                mac = None
                for i, p in enumerate(parts):
                    if 'P2P-GO-NEG-REQUEST' in p and i + 1 < len(parts):
                        mac = parts[i + 1]
                        break

                if mac:
                    log(f'GO-NEG-REQUEST from {mac}, responding')
                    r = ctrl_send(sock, server_path, 'P2P_STOP_FIND')
                    log(f'P2P_STOP_FIND: {r}')
                    r = ctrl_send(sock, server_path, f'P2P_CONNECT {mac} pbc go_intent=15')
                    log(f'P2P_CONNECT: {r}')
                else:
                    log('GO-NEG-REQUEST but could not parse MAC')

    finally:
        sock.close()
        try:
            os.unlink(client_path)
        except OSError:
            pass

if __name__ == '__main__':
    main()
