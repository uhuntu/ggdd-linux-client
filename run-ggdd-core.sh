#!/usr/bin/env bash
# Headless vendor core for systemd: refresh the profile, then exec the core on 19674/19091.
set -euo pipefail
cd "$(dirname "$0")"
export WINEDEBUG=-all WINEDLLOVERRIDES='mscoree,mshtml='

if ! ./refresh-native-profile.sh; then
  [[ -s runtime/profile.yaml ]] || { echo "Refresh failed and no cached profile exists." >&2; exit 1; }
  echo "Refresh failed; using the cached profile." >&2
fi
./ggdd-native-refresh.mjs prepare-vendor
exec ./run-ggdd-vendor-core.sh
