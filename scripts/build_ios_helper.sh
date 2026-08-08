#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || -z "$1" ]]; then
  echo "usage: $0 OUTPUT_PATH" >&2
  exit 64
fi

output="$1"
mkdir -p "$(dirname "$output")"
dart compile exe tool/duckmusic_ios_helper.dart -o "$output"
chmod 755 "$output"
