#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TVOS_REVISION=88a497e6345d32f2aedba92c1fdb30f42d29a3d3
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'Apple TV builds require macOS and Xcode.' >&2
  exit 1
fi
if [[ ! -d .tools/flutter-tvos/.git ]]; then
  mkdir -p .tools
  git clone https://github.com/fluttertv/flutter-tvos.git .tools/flutter-tvos
fi
if [[ "$(git -C .tools/flutter-tvos rev-parse HEAD)" != "$TVOS_REVISION" ]]; then
  if [[ -n "$(git -C .tools/flutter-tvos status --porcelain)" ]]; then
    echo 'The local tvOS toolchain has changes; preserve them before switching revisions.' >&2
    exit 1
  fi
  git -C .tools/flutter-tvos fetch origin "$TVOS_REVISION"
  git -C .tools/flutter-tvos checkout --detach "$TVOS_REVISION"
fi
.tools/flutter-tvos/bin/flutter-tvos precache
.tools/flutter-tvos/bin/flutter-tvos doctor
