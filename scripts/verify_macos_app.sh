#!/usr/bin/env bash
set -euo pipefail

fail() { printf 'macOS verification: %s\n' "$*" >&2; exit 1; }

if [[ $# -ne 5 ]]; then
  echo "usage: $0 APP_PATH arm64|x64 VERSION BUILD_NUMBER layout|development|release" >&2
  exit 64
fi

app="$1"
case "$2" in
  arm64) target_arch=arm64 ;;
  x64) target_arch=x86_64 ;;
  *) fail 'Unsupported target architecture.' ;;
esac
version="$3"
build_number="$4"
mode="$5"
case "$mode" in layout|development|release) ;; *) fail 'Invalid verification mode.' ;; esac

[[ -d "$app/Contents" && ! -L "$app" ]] || fail 'Missing app bundle.'
plist="$app/Contents/Info.plist"
[[ -f "$plist" ]] || fail 'Missing Info.plist.'
read_plist() { plutil -extract "$1" raw -o - "$plist"; }
[[ "$(read_plist CFBundleIdentifier)" == 'com.751152.duckMusic' ]] || fail 'Unexpected bundle identifier.'
[[ "$(read_plist CFBundleShortVersionString)" == "$version" ]] || fail 'Bundle version does not match the release.'
[[ "$(read_plist CFBundleVersion)" == "$build_number" ]] || fail 'Bundle build number does not match the release.'
executable="$(read_plist CFBundleExecutable)"
[[ -n "$executable" && "$executable" != */* ]] || fail 'Invalid bundle executable.'
main_binary="$app/Contents/MacOS/$executable"
helper="$app/Contents/Resources/duckmusic-ios-helper"
[[ -x "$main_binary" && ! -L "$main_binary" ]] || fail 'Missing app executable.'
[[ -x "$helper" && ! -L "$helper" ]] || fail 'Missing executable iOS helper; build it before packaging.'

binary_count=0
while IFS= read -r -d '' binary; do
  if [[ "$(file -b "$binary")" == *Mach-O* ]]; then
    lipo "$binary" -verify_arch "$target_arch" || fail "Missing $target_arch architecture: $binary"
    binary_count=$((binary_count + 1))
  fi
done < <(find "$app/Contents" -type f -print0)
[[ "$binary_count" -ge 2 ]] || fail 'App and helper must both be Mach-O executables.'
# Check these explicitly: a replaced helper must not escape the Mach-O scan.
for binary in "$main_binary" "$helper"; do
  [[ "$(file -b "$binary")" == *Mach-O* ]] || fail "Not a Mach-O executable: $binary"
done

if [[ "$mode" == layout ]]; then
  exit 0
fi

codesign --verify --deep --strict --verbose=2 "$app"
codesign --verify --strict --verbose=2 "$helper"

if [[ "$mode" == release ]]; then
  [[ "${APPLE_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] || fail 'A valid APPLE_TEAM_ID is required.'
  requirement="anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = \"${APPLE_TEAM_ID}\""
  # Apple scans every Mach-O, including executables stored in Resources.
  while IFS= read -r -d '' binary; do
    if [[ "$(file -b "$binary")" == *Mach-O* ]]; then
      codesign --verify --strict --test-requirement "$requirement" "$binary"
    fi
  done < <(find "$app/Contents" -type f -print0)
  for binary in "$main_binary" "$helper"; do
    signature="$(codesign --display --verbose=4 "$binary" 2>&1)"
    grep -Eq 'flags=.*[(,]runtime[,)]' <<< "$signature" || fail 'Hardened Runtime is required for app and helper.'
    grep -q '^Timestamp=' <<< "$signature" || fail 'A secure signing timestamp is required.'
  done
fi

printf 'Verified macOS %s app, version %s (%s), %s Mach-O files.\n' "$2" "$version" "$build_number" "$binary_count"
