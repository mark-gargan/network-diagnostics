# Network Diagnostics

Tools for diagnosing intermittent connection refused errors on a home network.

## Network Topology

```
Mac (192.168.68.x)
  → TP-Link Deco X50 mesh (192.168.68.1) — IPv4 NAT
    → Virgin Media Hub 6 (192.168.0.1) — DS-Lite (IPv4-in-IPv6 tunnel)
      → Virgin CGNAT / AFTR (aftr01.upc.ie)
        → Internet
```

- **DNS**: AdGuard Home at 192.168.68.65 (primary), Cloudflare 1.0.0.1 (secondary)
- **IPv4**: DS-Lite tunnelled — no native IPv4 WAN, all IPv4 goes through ISP AFTR
- **NAT**: Double NAT (Deco + CGNAT), no bridge mode available on Hub 6

## Findings So Far

- **Root cause**: Hard limit of ~2 concurrent outbound TCP connections
- **Symptom**: `Connection refused` (TCP RST) on port 443/80 to any external host
- **DNS is fine** — resolution works, the issue is at TCP connection layer
- **Not Tailscale** — tested with extension disabled, no change
- **Not the Virgin Hub** — it only has IPv6 firewall settings (IPv4 is tunnelled via DS-Lite)
- **Likely the Deco X50** — only device doing IPv4 NAT, suspected flood protection in firmware
- **Pending**: Check Deco HomeShield / Intrusion Prevention settings in the Deco app

## Scripts

### `concurrency-test.sh [host] [port]`
Tests outbound TCP concurrency limits. Finds the exact threshold where connections start failing.
```bash
./concurrency-test.sh              # default: 1.1.1.1:443
./concurrency-test.sh 8.8.8.8 443  # custom target
```

### `connection-monitor.sh [interval]`
Long-running monitor that cycles through multiple sites. Logs full diagnostics on every failure (curl exit code, DNS time, connect time, resolved IP, DNS server). Logs saved to `logs/`.
```bash
./connection-monitor.sh       # default 0.5s interval
./connection-monitor.sh 1     # 1 second between requests
```

### `hop-isolator.sh [deco_ip] [virgin_ip]`
Triggers a connection burst then immediately tests each network hop to isolate where blocking occurs.
```bash
./hop-isolator.sh                           # defaults
./hop-isolator.sh 192.168.68.1 192.168.0.1  # explicit IPs
```

### `dns-check.sh`
Quick DNS configuration and resolution speed check against all configured and common resolvers.

### `network-summary.sh`
One-shot overview: IPs, gateway, DNS, firewall status, connection stats, and traceroute.

## Quick Reference

```bash
# Run all checks
./network-summary.sh
./dns-check.sh
./concurrency-test.sh

# Start monitoring (Ctrl+C to stop, check logs/ for results)
./connection-monitor.sh

# After changing a setting, re-test concurrency
./concurrency-test.sh
```
