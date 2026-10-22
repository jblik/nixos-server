# CoolerControl's Graph profiles only accept temperature sources.

call() {
  curl -fsS -H "Authorization: Bearer $(<"$TOKEN_FILE")" "$API$1"
}

gpu=$(call /devices | jq -er --arg name "$GPU_DEVICE" 'first(.devices[] | select(.name == $name)) | .uid')

while true; do
  call "/status/$gpu" | jq -er --arg sensor "$GPU_SENSOR" '
    .status_history[-1] as $s
    | if any($s.channels[]; (.rpm // 0) > 0) then
        first($s.temps[] | select(.name == $sensor)) | (.temp * 1000 | round)
      else
        0
      end
  ' >"$TEMP_FILE.new"
  mv "$TEMP_FILE.new" "$TEMP_FILE"
  sleep 2
done
