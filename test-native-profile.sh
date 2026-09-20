#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
mihomo=/home/hunt/tools/ggdd-linux-wine-dashboard-bundle/mihomo
config="$root_dir/runtime/native-test.yaml"
log="$root_dir/runtime/native-test.log"
test_mihomo="$root_dir/runtime/ggdd-mihomo-test"
target_node="${GGDD_TEST_NODE:-A香港3-NF/GPT}"
profile_source="${GGDD_TEST_PROFILE_SOURCE:-}"

if [[ -n "$profile_source" ]]; then
  cp "$profile_source" "$config"
  sed -i \
    -e 's/^mixed-port:.*/mixed-port: 19674/' \
    -e "s|^external-controller:.*|external-controller: '127.0.0.1:19091'|" \
    -e 's/^allow-lan:.*/allow-lan: false/' \
    "$config"
  chmod 600 "$config"
  "$mihomo" -t -d "$root_dir/runtime" -f "$config" >/dev/null
  echo "Prepared isolated test from $(basename "$profile_source")."
else
  "$root_dir/ggdd-native-refresh.mjs" prepare-test
fi
ln -sfn "$mihomo" "$test_mihomo"
"$test_mihomo" -d "$root_dir/runtime" -f "$config" >"$log" 2>&1 &
test_pid=$!
cleanup() {
  kill "$test_pid" 2>/dev/null || true
  wait "$test_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

ready=0
for _ in {1..10}; do
  if curl -fsS --max-time 1 http://127.0.0.1:19091/version >/dev/null; then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" != 1 ]]; then
  echo "Native Mihomo did not become ready." >&2
  tail -30 "$log" >&2
  exit 1
fi

curl -fsS --max-time 5 -X PUT http://127.0.0.1:19091/proxies/GGDD \
  -H 'Content-Type: application/json' \
  --data "$(jq -nc --arg name "$target_node" '{name:$name}')"

selector_summary=$(curl -fsS --max-time 5 http://127.0.0.1:19091/proxies | \
  jq -r '.proxies | to_entries[] | select(.value.type == "Selector") | [.key,.value.now,(.value.all|length)] | @tsv')

echo "Selected node: $target_node"
echo "$selector_summary"

test_url() {
  local label=$1 url=$2 output rc
  set +e
  output=$(curl -sS --max-time 30 --proxy http://127.0.0.1:19674 "$url" 2>&1)
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then
    echo "$label: OK ($output)"
  else
    echo "$label: FAILED (curl $rc: $output)"
  fi
}

test_url "Native HTTP egress" http://api.ipify.org
echo "Waiting for the USB route watcher to learn the active server..."
sleep 12
test_url "Native HTTPS egress" https://api.ipify.org

sleep 1
echo "Recent Mihomo activity:"
tail -20 "$log"
