"""
UDP relay v3 - bridge phone and emulator via host multicast join.

How it works:
  1. Joins multicast group 224.0.0.167 on host's WiFi interface
  2. Listens on 0.0.0.0:53317 for phone's multicast packets
  3. Forwards phone's packets to emulator via ADB redir (127.0.0.1:53318)
  4. On the app side, emulator sends unicast to host (10.0.2.2),
     relay receives it and forwards to phone's IP via host WiFi

Usage: python udp_relay_v3.py
"""
import socket
import struct
import sys
import subprocess
import time

def get_usb_ip():
    """Get the IP of the USB tethering interface (192.168.42-43.x most common)"""
    r = subprocess.run(
        ["powershell", "-Command",
         "Get-NetAdapter -Name '*usb*' | Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress"],
        capture_output=True, text=True, timeout=5)
    ip = r.stdout.strip()
    if ip and ip != '':
        return ip.split('\n')[0].strip()

    # fallback: find any 192.168.43.x or 192.168.42.x
    r = subprocess.run(
        ["powershell", "-Command",
         "Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -like '192.168.4*' -or $_.IPAddress -like '192.168.3*' } | Select-Object -ExpandProperty IPAddress"],
        capture_output=True, text=True, timeout=5)
    ip = r.stdout.strip()
    if ip and ip != '':
        return ip.split('\n')[0].strip()
    return None

def get_phone_ip():
    """Get phone IP from adb"""
    r = subprocess.run(['adb', '-s', 'FMR0224521005953', 'shell', 'ip', '-f', 'inet', 'addr', 'show', 'wlan0'],
                       capture_output=True, text=True, timeout=5)
    for line in r.stdout.split('\n'):
        if 'inet ' in line:
            parts = line.strip().split()
            ip_cidr = parts[1] if len(parts) > 1 else ''
            return ip_cidr.split('/')[0]
    return None

HOST_IP = get_usb_ip()
if not HOST_IP:
    HOST_IP = "192.168.43.30"  # fallback USB tether IP
    print(f"[Relay] Using fallback USB IP: {HOST_IP}", flush=True)
else:
    print(f"[Relay] USB interface IP: {HOST_IP}", flush=True)

MCAST_GRP = "224.0.0.167"
MCAST_PORT = 53317
ADB_REDIR_5554 = 53318  # -> emulator-5554:53317
ADB_REDIR_5556 = 53319  # -> emulator-5556:53317

# Detect phone IP from last logcat entry
def get_phone_ip():
    r = subprocess.run(
        ["adb", "-s", "FMR0224521005953", "logcat", "-d", "-s", "Discovery", "-e", "本机IP"],
        capture_output=True, text=True, timeout=5)
    for line in r.stdout.split('\n')[::-1]:
        if '本机IP' in line or 'localIp' in line or 'IP:' in line:
            parts = line.split()
            for p in parts:
                if p.count('.') == 3:
                    return p
    return None

phone_ip = get_phone_ip()
if phone_ip:
    print(f"[Relay] Phone IP: {phone_ip}", flush=True)
else:
    print(f"[Relay] Phone IP not detected, forwarding to all known emulators", flush=True)

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.settimeout(2.0)

# Join multicast group on all interfaces
try:
    mreq = struct.pack("4sl", socket.inet_aton(MCAST_GRP), socket.INADDR_ANY)
    s.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
except Exception as e:
    print(f"[Relay] WARN: multicast join failed: {e}", flush=True)

try:
    s.bind(("0.0.0.0", MCAST_PORT))
    print(f"[Relay] LISTEN on 0.0.0.0:{MCAST_PORT} (joined {MCAST_GRP})", flush=True)
except OSError as e:
    print(f"[Relay] BIND FAIL: {e}", flush=True)
    sys.exit(1)

print(f"[Relay] ADB redir ports: 53318->5554, 53319->5556", flush=True)
if phone_ip:
    print(f"[Relay] Phone direct: {phone_ip}:53317", flush=True)
print("[Relay] Ready!", flush=True)

REDIR_PORTS = {53318, 53319}
seen = set()
last_phone_ip = phone_ip

while True:
    try:
        d, a = s.recvfrom(2048)
        sp = a[1]  # source port

        # Skip loopback from redir ports
        if sp in REDIR_PORTS or a[0] == '127.0.0.1':
            continue

        sip = a[0]
        if sip not in seen:
            seen.add(sip)
            print(f"[Relay] SEEN {sip}:{sp}", flush=True)
            # Try to detect phone IP from sender
            if sip != last_phone_ip and sip not in ('10.0.2.15', '10.0.2.16', '127.0.0.1'):
                last_phone_ip = sip
                print(f"[Relay] PHONE IP ← {sip}", flush=True)

        msg = d.decode("utf-8", "replace")[:50]

        # Forward to emulator via redir
        for rp in REDIR_PORTS:
            try:
                s.sendto(d, ("127.0.0.1", rp))
            except:
                pass

        # Forward to phone directly if known
        if sip in ('10.0.2.15', '10.0.2.16') and last_phone_ip and last_phone_ip not in ('10.0.2.15', '10.0.2.16'):
            try:
                s.sendto(d, (last_phone_ip, MCAST_PORT))
                print(f"[Relay] PHONE FWD {len(d)}B -> {last_phone_ip}:{MCAST_PORT} | {msg}", flush=True)
            except Exception as e:
                print(f"[Relay] PHONE FWD FAIL: {e}", flush=True)

        print(f"[Relay] RELAY {len(d)}B from {sip} -> redir:{REDIR_PORTS} | {msg}", flush=True)

    except socket.timeout:
        continue
    except Exception as e:
        print(f"[Relay] ERR: {e}", flush=True)
        continue
