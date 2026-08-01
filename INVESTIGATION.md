# Network Investigation: Intermittent Connection Refused

**Date**: 30–31 July 2026
**Reported symptom**: Intermittent "failed to connect" errors when browsing — not every request, but frequent enough to be noticeable. Affects any site, sometimes the HTML page, sometimes CSS/assets.

---

## Network Topology

```
Mac (192.168.68.x, Wi-Fi)
  → TP-Link Deco X50 mesh (192.168.68.1) — Router mode, IPv4 NAT, DHCP
    → Virgin Media Hub 6 (192.168.0.1) — DS-Lite (IPv4-in-IPv6 tunnel), CGNAT
      → Virgin ISP AFTR (aftr01.upc.ie) — Carrier-grade NAT
        → Internet
```

- **AdGuard Home**: Running at 192.168.68.65 on the local network
- **DNS via DHCP**: 192.168.68.65 (AdGuard), 1.0.0.1 (Cloudflare fallback)
- **IPv4 delivery**: DS-Lite — no native IPv4 WAN address, all IPv4 tunnelled over IPv6
- **NAT layers**: Triple — Deco → Virgin Hub → CGNAT

---

## Investigation Timeline

### Phase 1: DNS (ruled out)

**Initial hypothesis**: AdGuard DNS or DNS misconfiguration causing intermittent failures.

**Findings**:
- Mac had a manual DNS override (`1.1.1.1`) ignoring DHCP-provided servers
- DHCP was providing AdGuard (192.168.68.65) + Cloudflare (1.0.0.1)
- Fixed the override — DNS now correctly uses AdGuard as primary
- **DNS resolution worked consistently** — `dig` always returned results even during connection failures
- Failures were `Connection refused` (TCP RST), not DNS timeouts

**Conclusion**: DNS was misconfigured but not the cause of the intermittent failures.

### Phase 2: Connection Analysis

**Key observation**: Failures were `curl exit code 7` — connection refused. Verbose output showed TCP SYN to port 443 being refused with RST across all destination IPs.

**Delay threshold test** (initial, 30 July):

| Delay between requests | Failures |
|---|---|
| 0.5s | 0/50 (0%) |
| 0.3s | 9/50 (18%) |
| 0.2s | 19/50 (38%) |
| 0.1s | 22/50 (44%) |
| 0.05s | 25/50 (50%) |
| 0s | 30/50 (60%) |

This pattern indicated rate-based connection throttling.

### Phase 3: Concurrency Testing

Switched from sequential delay testing to concurrent connection testing. This revealed the true constraint.

**Concurrency test (30 July)**:

| Concurrent connections | Failures |
|---|---|
| 1–2 | 0% |
| 3 | 46% |
| 5 | 92% |
| 10+ | 90%+ |

**Hard limit of ~2 concurrent outbound TCP connections.** This is severe — a single web page loading multiple resources (HTML, CSS, JS, images) easily exceeds this.

### Phase 4: Isolating the Hop

**Tests performed**:
- During external TCP failures, both Deco (192.168.68.1) and Virgin Hub (192.168.0.1) responded normally on their local interfaces
- ICMP ping to external hosts worked during TCP failures
- UDP DNS to external servers worked during TCP failures
- Same failure rate regardless of destination IP or DNS server
- Same failure rate using Python `urllib` — not curl-specific

**Tailscale**: Network extension was running as root despite Tailscale being "stopped". Disabled it — no change in failure rate. Ruled out.

**Router logs (Deco)**: No firewall/block/rate-limit entries logged. Showed normal mesh management traffic (inter-node SSH, band steering, UPnP). TP-Link firmware doesn't log connection-level filtering.

**Modem logs (Virgin Hub 6)**: Clean. Only a DHCP renewal warning and historical reboot entries. No connection blocking logged.

### Phase 5: Upstream Investigation

**Virgin Media Hub 6 details**:
- Running DS-Lite — all IPv4 traffic tunnelled over IPv6 to `aftr01.upc.ie`
- No native IPv4 WAN address
- Hub only exposes **IPv6 firewall** settings (IPv4 is tunnelled, not routed)
- IPv6 firewall had "IP flood detection" enabled — disabled it, no change (expected, as test traffic was IPv4)
- DHCP settings available but **no option to set custom DNS servers**
- **No bridge/modem mode available**

### Phase 6: Re-test (31 July)

Without any definitive fix applied, re-ran concurrency test the following day:

**Concurrency test (31 July)**:

| Concurrent connections | Failures |
|---|---|
| 1–15 | 0% |
| 20 | 32% |
| 30 | 96% |

Significant improvement from the previous day's results (was failing at 3, now clean to 15). Possible explanations:
- Deco's IPS/flood protection state reset overnight
- The aggressive testing on the 30th may have triggered heightened protection that has since relaxed
- Thermal or load conditions on the Deco changed

---

## Conclusions

### Root Cause (most likely)
**TP-Link Deco X50 firmware-level flood/intrusion protection** is throttling outbound TCP connections. The Deco doesn't expose these settings to the user and doesn't log when it blocks connections. The behaviour is consistent with SYN flood protection that tracks connection rates per client and sends TCP RST when a threshold is exceeded.

### Contributing Factors
- **Double/triple NAT** (Deco → Virgin Hub → CGNAT) — each layer tracks connections
- **DS-Lite** — adds complexity to the IPv4 path, though the Virgin Hub's IPv4 firewall is bypassed since IPv4 is tunnelled
- **No user-accessible controls** — Deco X50 doesn't expose firewall/IPS tuning; Virgin Hub 6 doesn't expose IPv4 firewall or DNS-in-DHCP settings

### What's Not the Cause
- ❌ DNS resolution (works fine)
- ❌ Tailscale network extension (tested with it disabled)
- ❌ Virgin Hub IPv6 firewall / IP flood detection (IPv4 traffic is tunnelled)
- ❌ macOS firewall (disabled)
- ❌ Port exhaustion (nowhere near limits)

### Current Status
As of 31 July, the issue has improved significantly without intervention — concurrent connection threshold moved from 3 to 15+. Normal browsing should be unaffected at current levels.

---

## Potential Improvements (Not Yet Actioned)

1. **Deco HomeShield** — Check and disable Intrusion Prevention in the Deco app (most targeted fix)
2. **Deco AP mode** — Remove Deco's NAT/firewall entirely, let Virgin Hub route. Blocked by: Virgin Hub can't set custom DNS in DHCP, so AdGuard would need manual DNS config per device
3. **Virgin IPv4-only mode** — Request Virgin switch from DS-Lite to native IPv4. Would give the Hub a real IPv4 WAN address and expose IPv4 firewall controls. May also enable modem/bridge mode
4. **Monitor** — Use `connection-monitor.sh` to track if the issue recurs

---

## Test Scripts

All in `/Users/mark/code/network-diagnostics/`:

| Script | Purpose |
|---|---|
| `concurrency-test.sh` | Find concurrent connection limit threshold |
| `connection-monitor.sh` | Long-running failure logger with diagnostics |
| `hop-isolator.sh` | Identify which network hop is blocking |
| `dns-check.sh` | DNS config and resolution speed check |
| `network-summary.sh` | Quick network environment overview |
