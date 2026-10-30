awk -v interface="$NETWORK_INTERFACE:" '
  $1 == interface {
    print "# TYPE nordvpn_network_receive_bytes_total counter"
    print "nordvpn_network_receive_bytes_total " $2
    print "# TYPE nordvpn_network_transmit_bytes_total counter"
    print "nordvpn_network_transmit_bytes_total " $10
    found = 1
  }
  END { if (!found) exit 1 }
' /proc/net/dev >"$METRICS_DIRECTORY/nordvpn-traffic.prom.tmp"

printf 'nordvpn_traffic_timestamp_seconds %s\n' "$(date +%s)" >>"$METRICS_DIRECTORY/nordvpn-traffic.prom.tmp"
mv "$METRICS_DIRECTORY/nordvpn-traffic.prom.tmp" "$METRICS_DIRECTORY/nordvpn-traffic.prom"
