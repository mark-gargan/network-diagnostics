#!/bin/bash
# Quick network environment summary

echo "=== Network Summary ==="
echo "Hostname:    $(hostname)"
echo "Local IP:    $(ifconfig en0 | grep 'inet ' | awk '{print $2}')"
echo "Gateway:     $(netstat -rn | grep default | head -1 | awk '{print $2}')"
echo "DNS:         $(networksetup -getdnsservers Wi-Fi 2>/dev/null | tr '\n' ' ')"
echo "Interface:   en0"
echo ""

echo "=== Route to Internet ==="
route get 1.1.1.1 2>&1 | grep -E "destination|gateway|interface"
echo ""

echo "=== Firewall ==="
/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>&1
echo ""

echo "=== Network Extensions ==="
systemextensionsctl list 2>&1 | grep -E "enabled|active|network" | head -5
echo ""

echo "=== Connection Stats ==="
echo "Established: $(netstat -an -p tcp 2>/dev/null | grep -c ESTABLISHED)"
echo "TIME_WAIT:   $(netstat -an -p tcp 2>/dev/null | grep -c TIME_WAIT)"
echo "CLOSE_WAIT:  $(netstat -an -p tcp 2>/dev/null | grep -c CLOSE_WAIT)"
echo ""

echo "=== Traceroute (5 hops) ==="
traceroute -m 5 -w 2 -q 1 1.1.1.1 2>&1
