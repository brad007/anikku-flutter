#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x .tools/flutter-tvos/bin/flutter-tvos ]]; then
  echo 'Run ./tool/bootstrap_tvos.sh first.' >&2
  exit 1
fi
if [[ $# -eq 0 ]]; then
  .tools/flutter-tvos/bin/flutter-tvos devices
  echo 'Usage: ./tool/run_tvos.sh <device-id> [--release]' >&2
  exit 1
fi
device_id="$1"
shift
exec .tools/flutter-tvos/bin/flutter-tvos run -t lib/main.dart -d "$device_id" "$@"
