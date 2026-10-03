# Applies $DEFAULTS (see fans.nix) through the CoolerControl API when it differs from
# what was applied last, and keeps a dashboard token in $STATE_DIR/dashboard-token.

jar="$RUNTIME_DIRECTORY/cookies"
password=$(<"$PASSWORD_FILE")
token_file="$STATE_DIR/dashboard-token"
applied_file="$STATE_DIR/applied"

call() {
  local method=$1 path=$2
  shift 2
  curl -fsS -b "$jar" -c "$jar" -X "$method" -H 'Content-Type: application/json' "$@" "$API$path"
}

login() {
  curl -fsS -c "$jar" -u "CCAdmin:$1" -X POST "$API/login" >/dev/null
}

for _ in $(seq 60); do
  curl -fsS -o /dev/null "$API/handshake" && break
  sleep 1
done

if ! login "$password"; then
  echo "Replacing the default password"
  login coolAdmin
  call POST /set-passwd -u "CCAdmin:$password" --data '{"current_password":"coolAdmin"}' >/dev/null
  login "$password"
fi

if ! { [[ -s $token_file ]] && curl -fsS -o /dev/null -H "Authorization: Bearer $(<"$token_file")" "$API/metrics"; }; then
  echo "Creating the dashboard token"
  call POST /tokens --data '{"label":"server-dashboard","write_access":true}' | jq -er .token >"$token_file.new"
  mv "$token_file.new" "$token_file"
fi

if [[ "$(cat "$applied_file" 2>/dev/null)" == "$DEFAULTS" ]]; then
  echo "Defaults unchanged since they were last applied"
  exit 0
fi

jq -c .settings "$DEFAULTS" | call PATCH /settings --data @- >/dev/null

devices=$(call GET /devices)

resolve_sensor() {
  jq -c --argjson devices "$devices" '
    if .temp_source then
      .temp_source as $s
      | (first($devices.devices[] | select(.name == $s.device or .info.model == $s.device))
          // error("no device \($s.device)")) as $d
      | .temp_source = {
          device_uid: $d.uid,
          temp_name: (first($d.info.temps | to_entries[] | select(.key == $s.sensor or .value.label == $s.sensor) | .key)
            // error("no sensor \($s.sensor) on \($s.device)"))
        }
    end'
}

upsert() {
  local collection=$1 entity=$2 uid
  uid=$(jq -r .uid <<<"$entity")
  if call GET "/$collection" | jq -e --arg uid "$uid" ".${collection}[] | select(.uid == \$uid)" >/dev/null; then
    call PUT "/$collection" --data "$entity" >/dev/null
  else
    call POST "/$collection" --data "$entity" >/dev/null
  fi
}

jq -c '.functions[]' "$DEFAULTS" | while read -r function; do
  upsert functions "$function"
done

jq -c '.profiles[]' "$DEFAULTS" | while read -r profile; do
  upsert profiles "$(resolve_sensor <<<"$profile")"
done

board=$(jq -er --arg name "$(jq -r .device "$DEFAULTS")" 'first(.devices[] | select(.name == $name)) | .uid' <<<"$devices")

mode_uid() {
  call GET /modes | jq -r --arg name "$1" 'first(.modes[] | select(.name == $name)) | .uid // empty'
}

jq -c '.modes[]' "$DEFAULTS" | while read -r mode; do
  name=$(jq -r .name <<<"$mode")
  echo "Saving mode $name"
  jq -r '.channels | to_entries[] | "\(.key) \(.value)"' <<<"$mode" | while read -r channel profile; do
    call PUT "/devices/$board/settings/$channel/profile" --data "$(jq -n --arg uid "$profile" '{profile_uid: $uid}')" >/dev/null
  done
  uid=$(mode_uid "$name")
  if [[ -n $uid ]]; then
    call PUT "/modes/$uid/settings" >/dev/null
  else
    call POST /modes --data "$(jq -n --arg name "$name" '{name: $name}')" >/dev/null
  fi
done

call POST "/modes-active/$(mode_uid "$(jq -r '.modes[0].name' "$DEFAULTS")")" >/dev/null
echo "$DEFAULTS" >"$applied_file"
echo "Applied $DEFAULTS"
