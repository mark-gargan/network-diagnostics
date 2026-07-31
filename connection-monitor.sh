#!/bin/bash
# Long-running connection monitor
# Cycles through multiple sites, logs failures with full diagnostics

TARGETS=(
  "https://www.google.com"
  "https://www.cloudflare.com"
  "https://www.apple.com"
  "https://github.com"
  "https://amazon.com"
)

LOGFILE="$(dirname "$0")/logs/monitor-$(date +%Y-%m-%d_%H%M%S).log"
mkdir -p "$(dirname "$LOGFILE")"

COUNT=0
FAILURES=0
INTERVAL="${1:-0.5}"

echo "Connection monitor started at $(date)" | tee "$LOGFILE"
echo "Targets: ${TARGETS[*]}" | tee -a "$LOGFILE"
echo "Interval: ${INTERVAL}s" | tee -a "$LOGFILE"
echo "Log: $LOGFILE" | tee -a "$LOGFILE"
echo "Press Ctrl+C to stop" | tee -a "$LOGFILE"
echo "---" | tee -a "$LOGFILE"

trap 'echo ""; echo "=== Summary ===" | tee -a "$LOGFILE"; echo "Total requests: $COUNT" | tee -a "$LOGFILE"; echo "Failures: $FAILURES" | tee -a "$LOGFILE"; if [ $COUNT -gt 0 ]; then echo "Failure rate: $(echo "scale=2; $FAILURES * 100 / $COUNT" | bc)%" | tee -a "$LOGFILE"; fi; exit 0' INT

while true; do
  for url in "${TARGETS[@]}"; do
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
      dns_server=$(scutil --dns | grep "nameserver\[0\]" | head -1 | awk '{print $3}')

      {
        echo "[$ts] FAIL #$FAILURES (req #$COUNT)"
        echo "  URL:        $url"
        echo "  curl_exit:  $exit_code"
        echo "  http_code:  $http_code"
        echo "  dns_time:   ${dns_time}s"
        echo "  conn_time:  ${conn_time}s"
        echo "  total_time: ${total_time}s"
        echo "  remote_ip:  $remote_ip"
        echo "  dns_server: $dns_server"
        echo "  dig_result: $dns_check"
        echo ""
      } | tee -a "$LOGFILE"
    else
      if [ $((COUNT % 50)) -eq 0 ]; then
        echo "[$ts] $COUNT requests, $FAILURES failures so far" | tee -a "$LOGFILE"
      else
        printf "."
      fi
    fi

    sleep "$INTERVAL"
  done
done
