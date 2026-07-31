#!/bin/bash
# Quick DNS configuration and resolution check

echo "=== DNS Configuration ==="
echo "Configured servers:"
networksetup -getdnsservers Wi-Fi 2>/dev/null || echo "  (unable to query)"
echo ""
echo "DHCP-provided servers:"
ipconfig getpacket en0 2>/dev/null | grep domain_name_server
echo ""

echo "=== Active Resolver ==="
scutil --dns | head -8
echo ""

echo "=== Resolution Test ==="
for server in "default" "192.168.68.65" "1.0.0.1" "1.1.1.1" "8.8.8.8"; do
  if [ "$server" = "default" ]; then
    time_ms=$(dig google.com +short +time=3 +tries=1 2>&1 | tail -1)
    result=$(dig google.com +stats +time=3 +tries=1 2>&1 | grep "Query time" | awk '{print $4}')
    echo "  Default resolver:  ${result}ms"
  else
    result=$(dig google.com @"$server" +stats +time=3 +tries=1 2>&1 | grep "Query time" | awk '{print $4}')
    echo "  @${server}: ${result}ms"
  fi
done
