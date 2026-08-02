#!/bin/bash
# Fixed-duration connection test for fair A/B comparison
# Usage: ./timed-test.sh [duration_seconds] [label]

DURATION="${1:-300}"
LABEL="${2:-test}"

TARGETS=(
  "https://www.google.com"
  "https://www.cloudflare.com"
  "https://www.apple.com"
  "https://github.com"
  "https://amazon.com"
)

LOGFILE="$(dirname "$0")/logs/timed-${LABEL}-$(date +%Y-%m-%d_%H%M%S).log"
mkdir -p "$(dirname "$LOGFILE")"

COUNT=0
FAILURES=0
INTERVAL=0.5
END_TIME=$(( $(date +%s) + DURATION ))

# Collect environment info
LOCAL_IP=$(ifconfig en0 | grep 'inet ' | awk '{print $2}')
GATEWAY=$(netstat -rn | grep default | head -1 | awk '{print $2}')
SSID=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | grep ' SSID' | awk '{print $2}')
DNS=$(networksetup -getdnsservers Wi-Fi 2>/dev/null | tr '\n' ' ')

{
  echo "=== Timed Test: $LABEL ==="
  echo "Started:   $(date)"
  echo "Duration:  ${DURATION}s"
  echo "SSID:      $SSID"
  echo "Local IP:  $LOCAL_IP"
  echo "Gateway:   $GATEWAY"
  echo "DNS:       $DNS"
  echo "Targets:   ${TARGETS[*]}"
  echo "Interval:  ${INTERVAL}s"
  echo "---"
} | tee "$LOGFILE"

while [ $(date +%s) -lt $END_TIME ]; do
  for url in "${TARGETS[@]}"; do
    # Check time limit before each request
    [ $(date +%s) -ge $END_TIME ] && break

    COUNT=$((COUNT + 1))
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    domain=$(echo "$url" | awk -F/ '{print $3}')

    result=$(curl -s -o /dev/null -w \
      "http_code:%{http_code} time_namelookup:%{time_namelookup} time_connect:%{time_connect} time_total:%{time_total} remote_ip:%{remote_ip}" \
      --connect-timeout 5 --max-time 10 "$url" 2>&1)
    exit_code=$?

    http_code=$(echo "$result" | grep -o 'http_code:[^ ]*' | cut -d: -f2)
    dns_time=$(echo "$result" | grep -o 'time_namelookup:[^ ]*' | cut -d: -f2)
    conn_time=$(echo "$result" | grep -o 'time_connect:[^ ]*' | cut -d: -f2)
    total_time=$(echo "$result" | grep -o 'time_total:[^ ]*' | cut -d: -f2)
    remote_ip=$(echo "$result" | grep -o 'remote_ip:[^ ]*' | cut -d: -f2)

    if [ $exit_code -ne 0 ] || [ "$http_code" = "000" ]; then
      FAILURES=$((FAILURES + 1))
      dns_check=$(dig "$domain" +short +time=2 +tries=1 2>&1 | head -3)

      {
        echo "[$ts] FAIL #$FAILURES (req #$COUNT)"
        echo "  URL:        $url"
        echo "  curl_exit:  $exit_code"
        echo "  http_code:  $http_code"
        echo "  dns_time:   ${dns_time}s"
        echo "  conn_time:  ${conn_time}s"
        echo "  total_time: ${total_time}s"
        echo "  remote_ip:  $remote_ip"
        echo "  dig_result: $dns_check"
        echo ""
      } | tee -a "$LOGFILE"
    else
      printf "."
    fi

    sleep "$INTERVAL"
  done
done

echo ""
{
  echo "=== Results: $LABEL ==="
  echo "Finished:  $(date)"
  echo "Requests:  $COUNT"
  echo "Failures:  $FAILURES"
  if [ $COUNT -gt 0 ]; then
    RATE=$(echo "scale=1; $FAILURES * 100 / $COUNT" | bc)
    echo "Fail rate: ${RATE}%"
  fi
  echo "Log:       $LOGFILE"
} | tee -a "$LOGFILE"
