#!/bin/bash
# Isolate which network hop is causing connection failures
# Tests: Deco → Virgin modem → External, during failure conditions

DECO="${1:-192.168.68.1}"
VIRGIN="${2:-192.168.0.1}"

echo "Hop isolator — Deco: $DECO, Virgin: $VIRGIN"
echo "---"

python3 -c "
import socket, concurrent.futures, time

DECO = '${DECO}'
VIRGIN = '${VIRGIN}'

def tcp_connect(host, port, timeout=2):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect((host, port))
        s.close()
        return True
    except Exception as e:
        return str(e)

# Trigger throttle with parallel burst
print('Phase 1: Triggering with 30 parallel connections...')
with concurrent.futures.ThreadPoolExecutor(max_workers=30) as pool:
    futures = [pool.submit(tcp_connect, '142.250.200.4', 443, 2) for _ in range(30)]
    results = [f.result() for f in futures]
    fails = sum(1 for r in results if r is not True)
    print(f'  Burst result: {fails}/30 failures')

print()
print('Phase 2: Testing each hop immediately after burst...')

targets = [
    (DECO, 80, 'Deco (LAN)'),
    (VIRGIN, 80, 'Virgin modem'),
    ('1.1.1.1', 443, 'Cloudflare (ext)'),
    ('8.8.8.8', 443, 'Google DNS (ext)'),
]

for host, port, name in targets:
    r = tcp_connect(host, port)
    status = 'OK' if r is True else f'FAIL ({r})'
    print(f'  {name:25s}: {status}')

# UDP test
print()
print('Phase 3: UDP DNS (should work even if TCP is blocked)...')
import struct
def udp_dns(server):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.settimeout(2)
        q = b'\xaa\xbb\x01\x00\x00\x01\x00\x00\x00\x00\x00\x00\x06google\x03com\x00\x00\x01\x00\x01'
        s.sendto(q, (server, 53))
        s.recvfrom(512)
        s.close()
        return True
    except:
        return False

for server in ['1.1.1.1', '8.8.8.8']:
    print(f'  UDP DNS {server}: {\"OK\" if udp_dns(server) else \"FAIL\"}')
"
