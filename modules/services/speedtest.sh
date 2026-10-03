# Runs one Ookla speedtest and writes the result for node_exporter's textfile collector
# to $RUNTIME_DIRECTORY/speedtest.prom. The dashboard reads these metric names.

result=$(speedtest --accept-license --accept-gdpr --format=json | jq -c 'select(.type == "result")')

# packetLoss is absent when the server cannot measure it; NaN keeps the sample present.
jq -r '
  "speedtest_download_bytes_per_second \(.download.bandwidth)",
  "speedtest_upload_bytes_per_second \(.upload.bandwidth)",
  "speedtest_ping_latency_seconds \(.ping.latency / 1000)",
  "speedtest_ping_jitter_seconds \(.ping.jitter / 1000)",
  "speedtest_download_latency_seconds \(.download.latency.iqm / 1000)",
  "speedtest_upload_latency_seconds \(.upload.latency.iqm / 1000)",
  "speedtest_packet_loss_ratio \(if .packetLoss == null then "NaN" else .packetLoss / 100 end)",
  "speedtest_timestamp_seconds \(.timestamp | fromdateiso8601)"
' <<<"$result" >"$RUNTIME_DIRECTORY/speedtest.prom.tmp"

mv "$RUNTIME_DIRECTORY/speedtest.prom.tmp" "$RUNTIME_DIRECTORY/speedtest.prom"
