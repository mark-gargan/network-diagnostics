#!/bin/bash
# DNS/Connection intermittent failure test
# Hits multiple sites, logs every failure with diagnostic info

TARGETS=(
  "https://www.google.com"
  "https://www.cloudflare.com"
  "https://www.apple.com"
  "https://github.com"
  "https://amazon.com"
)

LOGFILE="/Users/mark/code/dns-test.log"
COUNT=0
FAILURES=0
INTERVAL=0.5  # seconds between requests

echo "Starting connection test at $(date)" | tee "$LOGFILE"
echo "Targets: ${TARGETS[*]}" | tee -a "$LOGFILE"
echo "Press Ctrl+C to stop" | tee -a "$LOGFILE"
echo "---" | tee -a "$LOGFILE"

trap 'echo ""; echo "=== Summary ===" | tee -a "$LOGFILE"; echo "Total requests: $COUNT" | tee -a "$LOGFILE"; echo "Failures: $FAILURES" | tee -a "$LOGFILE"; echo "Failure rate: $(echo "scale=2; $FAILURES * 100 / $COUNT" | bc 2>/dev/null || echo "n/a")%" | tee -a "$LOGFILE"; exit 0' INT

while true; do
  for url in "${TARGETS[@]}"; do
    COUNT=$((COUNT + 1))
    ts=$(date '+%Y-%m-%d %H:%M:%S.%N' | cut -c1-23)
    domain=$(echo "$url" | awk -F/ '{print $3}')

    # Capture curl with detailed timing and error info
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
      # Get curl error message
      curl_err=$(curl -s -o /dev/null --connect-timeout 5 --max-time 10 "$url" 2>&1; echo "exit:$?")

      # Capture DNS state at time of failure
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
        echo "  curl_err:   $curl_err"
        echo ""
      } | tee -a "$LOGFILE"
    else
      # Print a dot for success, periodic status every 50 requests
      if [ $((COUNT % 50)) -eq 0 ]; then
        echo "[$ts] $COUNT requests, $FAILURES failures so far" | tee -a "$LOGFILE"
      else
        printf "."
      fi
    fi

    sleep "$INTERVAL"
  done
done
