#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -eq 0 ]]; then
  echo 'Usage: ./tool/test_tvos.sh <device-id> [--dart-define=TEST_NETWORK=true]' >&2
  exit 1
fi
device_id="$1"
shift
exec .tools/flutter-tvos/bin/flutter-tvos drive --driver=test_driver/integration_test.dart --target=integration_test/tvos_test.dart -d "$device_id" "$@"
