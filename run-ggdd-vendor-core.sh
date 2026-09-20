#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "$0")" && pwd)"
wine_prefix=/home/hunt/tools/ggdd-linux-wine-dashboard-bundle/ggdd-full-wine-bundle/.wine-prefix
sidecar="$wine_prefix/drive_c/Program Files/GGDD/resources/sidecar/mihomo.exe"
config='Z:\home\hunt\Desktop\ggdd-linux-client\runtime\vendor-profile.yaml'
data='Z:\home\hunt\Desktop\ggdd-linux-client\runtime'
xor_key='SIzLm51puIlCewdfDWCgWXQ_Kq-ST242UBEVBhKReO7guLPFH0='

[[ -x /usr/bin/wine64 ]] || { echo "wine64 is required." >&2; exit 1; }
[[ -f "$sidecar" ]] || { echo "GGDD vendor core is missing." >&2; exit 1; }
[[ -s "$root_dir/runtime/vendor-profile.yaml" ]] || {
  echo "Prepared vendor profile is missing." >&2
  exit 1
}

export WINEPREFIX="$wine_prefix"
exec /usr/bin/wine64 "$sidecar" \
  --xor-config "$config" \
  --xor-key "$xor_key" \
  -d "$data" \
  -ext-ctl 127.0.0.1:19091
