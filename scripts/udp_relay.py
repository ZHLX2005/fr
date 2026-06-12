"""
UDP 中继脚本 — 桥接 Android 模拟器之间的 UDP 多播
用法: python udp_relay.py

原理：
  两个模拟器各自在 10.0.2.x 独立 NAT 中，多播包无法互通。
  但两者都能访问 10.0.2.2（宿主机）。
  此脚本在宿主机监听 N 个模拟器的注册包，然后互相转发。
"""

import socket
import threading
import time

MULTICAST_ADDR = "224.0.0.167"
MULTICAST_PORT = 53317
HOST_PORT = 53317

# 已发现的模拟器
emulators: set[tuple[str, int]] = set()
emulators_lock = threading.Lock()


def relay_worker():
    """在宿主机上绑定 53317 端口，接收模拟器的单播包并广播给所有其他模拟器"""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.settimeout(5.0)

    try:
        sock.bind(("0.0.0.0", HOST_PORT))
        print(f"[Relay] 监听 0.0.0.0:{HOST_PORT}")
    except OSError as e:
        print(f"[Relay] 绑定失败: {e}")
        return

    while True:
        try:
            data, addr = sock.recvfrom(2048)
            src_ip, src_port = addr

            # 记录来源
            with emulators_lock:
                was_new = (src_ip, src_port) not in emulators
                emulators.add((src_ip, src_port))
                targets = list(emulators)

            if was_new:
                print(f"[Relay] 发现新设备: {src_ip}:{src_port} (共 {len(targets)} 台)")

            # 转发给所有其他模拟器
            for dst_ip, dst_port in targets:
                if (dst_ip, dst_port) == (src_ip, src_port):
                    continue
                try:
                    sent = sock.sendto(data, (dst_ip, dst_port))
                    print(f"[Relay] 转发 {len(data)} bytes: {src_ip} → {dst_ip}:{dst_port}")
                except Exception as e:
                    print(f"[Relay] 转发失败 {src_ip}→{dst_ip}: {e}")

        except socket.timeout:
            continue
        except Exception as e:
            print(f"[Relay] 错误: {e}")
            continue


def main():
    print("=" * 50)
    print("UDP 中继 — 桥接 Android 模拟器多播")
    print("=" * 50)
    print(f"监听端口: {HOST_PORT}")
    print(f"本机 IP  : 10.0.2.2 (模拟器视角)")
    print("")

    t = threading.Thread(target=relay_worker, daemon=True)
    t.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\n[Relay] 停止")


if __name__ == "__main__":
    main()
