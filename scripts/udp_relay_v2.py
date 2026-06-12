"""
UDP relay for Android emu bridge.
Usage: python udp_relay_v2.py
"""
import socket, sys

HOST_PORT = 53317
# Forward ALL received packets to both emulators' redir ports
REDIR_PORTS = [53318, 53319]  # -> emulator-5554, emulator-5556

s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.settimeout(3.0)

try:
    s.bind(("0.0.0.0", HOST_PORT))
    print(f"[Relay] LISTEN 0.0.0.0:{HOST_PORT}", flush=True)
    print(f"[Relay] FWD TO PORTS: {REDIR_PORTS}", flush=True)
except OSError as e:
    print(f"[Relay] BIND FAIL: {e}", flush=True)
    sys.exit(1)

seen = set()
while True:
    try:
        d, a = s.recvfrom(2048)
        sip = a[0]
        if sip not in seen:
            seen.add(sip)
            print(f"[Relay] SEEN {sip}", flush=True)
        # Forward to ALL redir ports (each emu filters by deviceId)
        for rp in REDIR_PORTS:
            try:
                s.sendto(d, ("127.0.0.1", rp))
            except Exception as e:
                print(f"[Relay] FWD FAIL 127.0.0.1:{rp} {e}", flush=True)
        msg = d.decode("utf-8", "replace")[:50]
        print(f"[Relay] FWD {len(d)}B -> {REDIR_PORTS} | {msg}", flush=True)
    except socket.timeout:
        continue
    except Exception as e:
        print(f"[Relay] ERR {e}", flush=True)
        continue
