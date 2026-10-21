prefix=${SPEEDTEST_PREFIX:-speedtest}

result=$(speedtest "$@" --accept-license --accept-gdpr --format=json | jq -c 'select(.type == "result")')

# packetLoss is absent when the server cannot measure it; NaN keeps the sample present.
jq -r --arg prefix "$prefix" '
  "\($prefix)_download_bytes_per_second \(.download.bandwidth)",
  "\($prefix)_upload_bytes_per_second \(.upload.bandwidth)",
  "\($prefix)_ping_latency_seconds \(.ping.latency / 1000)",
  "\($prefix)_ping_jitter_seconds \(.ping.jitter / 1000)",
  "\($prefix)_download_latency_seconds \(.download.latency.iqm / 1000)",
  "\($prefix)_upload_latency_seconds \(.upload.latency.iqm / 1000)",
  "\($prefix)_packet_loss_ratio \(if .packetLoss == null then "NaN" else .packetLoss / 100 end)",
  "\($prefix)_timestamp_seconds \(.timestamp | fromdateiso8601)"
' <<<"$result" >"$METRICS_DIRECTORY/$prefix.prom.tmp"

mv "$METRICS_DIRECTORY/$prefix.prom.tmp" "$METRICS_DIRECTORY/$prefix.prom"
