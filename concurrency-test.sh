#!/bin/bash
# Test outbound TCP concurrency limits
# Finds the threshold where connections start getting refused

TARGET_HOST="${1:-1.1.1.1}"
TARGET_PORT="${2:-443}"
ROUNDS=5

echo "Concurrency test → ${TARGET_HOST}:${TARGET_PORT} (${ROUNDS} rounds each)"
echo "---"

python3 -c "
import socket, concurrent.futures, time, sys

host = '${TARGET_HOST}'
port = ${TARGET_PORT}
rounds = ${ROUNDS}

def tcp_connect(host, port, timeout=2):
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.settimeout(timeout)
        s.connect((host, port))
        s.close()
        return True
    except:
        return False

for concurrency in [1, 2, 3, 5, 8, 10, 15, 20, 30]:
    fails = 0
    for _ in range(rounds):
        with concurrent.futures.ThreadPoolExecutor(max_workers=concurrency) as pool:
            futures = [pool.submit(tcp_connect, host, port, 2) for _ in range(concurrency)]
            results = [f.result() for f in futures]
            fails += sum(1 for r in results if not r)
        time.sleep(1)
    total = concurrency * rounds
    pct = 100 * fails // total
    bar = '█' * (pct // 5) + '░' * (20 - pct // 5)
    print(f'  Concurrency {concurrency:2d}: {fails:3d}/{total:3d} failures ({pct:3d}%) {bar}')
"
