#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
java_root=/usr/lib/jvm/java-17-openjdk-amd64
java_cmd="$java_root/bin/java"
javac_cmd="$java_root/bin/javac"
if [[ ! -x "$java_cmd" || ! -x "$javac_cmd" || ! -f "$java_root/lib/libawt_xawt.so" ]]; then
  echo "A full Java desktop runtime is required (openjdk-17-jre)." >&2
  exit 1
fi
"$javac_cmd" GgddLinuxClient.java

controller="http://127.0.0.1:19091"
core_pid=""
cleanup() {
  if [[ -n "$core_pid" ]]; then
    kill "$core_pid" 2>/dev/null || true
    wait "$core_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

if ! curl -fsS --max-time 1 "$controller/version" >/dev/null 2>&1; then
  if ! ./refresh-native-profile.sh; then
    [[ -s runtime/profile.yaml ]] || {
      echo "Unable to refresh GGDD and no cached native profile exists." >&2
      exit 1
    }
    echo "Refresh failed; using the cached native profile." >&2
  fi
  ./ggdd-native-refresh.mjs prepare-vendor
  ./run-ggdd-vendor-core.sh >runtime/vendor-core.log 2>&1 &
  core_pid=$!
  ready=0
  for _ in {1..20}; do
    if curl -fsS --max-time 1 "$controller/version" >/dev/null 2>&1; then
      ready=1
      break
    fi
    kill -0 "$core_pid" 2>/dev/null || break
    sleep 1
  done
  if [[ "$ready" != 1 ]]; then
    echo "GGDD vendor core did not become ready." >&2
    tail -30 runtime/vendor-core.log >&2
    exit 1
  fi
fi
export GGDD_CONTROLLER="$controller"

runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
auth_candidates=("${XAUTHORITY:-}")
while IFS= read -r auth; do auth_candidates+=("$auth"); done < <(find "$runtime_dir" -maxdepth 1 -type f \( -name '*Xwaylandauth*' -o -name '.mutter-Xwaylandauth*' \) -print 2>/dev/null)
display_ok=0
for socket in /tmp/.X11-unix/X*; do
  [[ -S "$socket" ]] || continue
  number="${socket##*X}"
  for auth in "${auth_candidates[@]}" ""; do
    [[ -n "$auth" ]] && export XAUTHORITY="$auth" || unset XAUTHORITY
    export DISPLAY=":$number"
    if command -v xdpyinfo >/dev/null 2>&1 && xdpyinfo >/dev/null 2>&1; then
      display_ok=1
      break 2
    fi
  done
done
if [[ "$display_ok" != 1 ]]; then
  unset DISPLAY XAUTHORITY
  echo "No graphical display detected; listing GGDD groups instead."
  "$java_cmd" GgddLinuxClient --list
  exit
fi
"$java_cmd" GgddLinuxClient "$@"
