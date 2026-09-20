#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec node ./ggdd-native-refresh.mjs refresh
