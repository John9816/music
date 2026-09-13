#!/usr/bin/env bash
set +x
set -euo pipefail

fail() { printf 'macOS packaging: %s\n' "$*" >&2; exit 1; }

if [[ $# -ne 6 ]]; then
  echo "usage: $0 APP_PATH arm64|x64 VERSION BUILD_NUMBER OUTPUT_DIR development|release" >&2
  exit 64
fi

source_app="$1"
arch="$2"
version="$3"
build_number="$4"
output_dir="$5"
mode="$6"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
entitlements="$script_dir/../macos/Runner/Release.entitlements"
helper_entitlements="$script_dir/../macos/Runner/Helper.entitlements"
case "$mode" in
  release)
    for name in MACOS_SIGNING_IDENTITY APPLE_TEAM_ID MACOS_KEYCHAIN MACOS_NOTARIZATION_PROFILE; do
      [[ -n "${!name:-}" ]] || fail "Required release configuration is missing: $name"
    done
    [[ "$MACOS_SIGNING_IDENTITY" == 'Developer ID Application: '* ]] || fail 'A Developer ID Application identity is required.'
    [[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail 'Invalid APPLE_TEAM_ID.'
    [[ -f "$MACOS_KEYCHAIN" ]] || fail 'The isolated signing keychain is missing.'
    sign_args=(--force --options runtime --timestamp --sign "$MACOS_SIGNING_IDENTITY" --keychain "$MACOS_KEYCHAIN")
    suffix=''
    ;;
  development)
    sign_args=(--force --timestamp=none --sign -)
    suffix='-development'
    ;;
  *) fail 'Explicit development or release mode is required.' ;;
esac

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$build_number" =~ ^[1-9][0-9]*$ ]] || fail 'Invalid release version or build number.'
bash "$script_dir/verify_macos_app.sh" "$source_app" "$arch" "$version" "$build_number" layout
[[ "$source_app" == *.app ]] || fail 'Expected an .app bundle.'
filename="DuckMusic-Flutter-v${version}-macOS-${arch}${suffix}.dmg"
[[ ! -e "$output_dir/$filename" ]] || fail 'Refusing to replace an existing package.'

# All mutations happen in a private copy. The Xcode product remains available
# for comparison, and a failed check never leaves a release asset in dist.
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/duckmusic-macos-package.XXXXXX")"
mountpoint="$work_dir/mount"
mounted=false
cleanup() {
  status=$?
  trap - EXIT
  if [[ "$mounted" == true ]]; then
    if ! hdiutil detach "$mountpoint" >/dev/null; then
      echo "Could not detach diagnostic mount: $mountpoint; temporary files retained." >&2
      exit 1
    fi
  fi
  # This directory was created by mktemp above and contains only this package.
  if [[ "$work_dir" == */duckmusic-macos-package.* && -d "$work_dir" ]]; then
    rm -rf -- "$work_dir"
  fi
  exit "$status"
}
trap cleanup EXIT
mkdir -p "$work_dir/app" "$work_dir/dmg-root" "$mountpoint"
app="$work_dir/app/$(basename "$source_app")"
ditto "$source_app" "$app"

# Sign each actual Mach-O first. --deep alone does not discover every helper
# in Resources. Sign framework/nested bundles next, then seal the outer app.
while IFS= read -r -d '' binary; do
  if [[ "$(file -b "$binary")" == *Mach-O* ]]; then
    if [[ "$binary" == "$app/Contents/Resources/duckmusic-ios-helper" ]]; then
      codesign "${sign_args[@]}" --entitlements "$helper_entitlements" "$binary"
    else
      codesign "${sign_args[@]}" "$binary"
    fi
  fi
done < <(find "$app/Contents" -type f -print0)
while IFS= read -r -d '' bundle; do
  codesign "${sign_args[@]}" "$bundle"
done < <(find "$app/Contents" -depth -type d \( -name '*.framework' -o -name '*.app' -o -name '*.xpc' -o -name '*.appex' \) -print0)
codesign "${sign_args[@]}" --entitlements "$entitlements" "$app"
bash "$script_dir/verify_macos_app.sh" "$app" "$arch" "$version" "$build_number" "$mode"

notarize() {
  local artifact="$1"
  local result="$work_dir/notary-$2.json"
  local command_exit=0
  xcrun notarytool submit "$artifact" \
    --keychain-profile "$MACOS_NOTARIZATION_PROFILE" --keychain "$MACOS_KEYCHAIN" \
    --wait --timeout 30m --output-format json > "$result" || command_exit=$?
  local status submission_id diagnostic summary issues
  status="$(plutil -extract status raw -o - "$result" 2>/dev/null || true)"
  if [[ "$command_exit" == 0 && "$status" == Accepted ]]; then
    return
  fi
  # Preserve actionable failure information in CI logs before the private
  # staging directory is cleaned. Do not dump keychain/profile credentials.
  case "$status" in Accepted|Invalid|Rejected|'In Progress') ;; *) status=Unknown ;; esac
  submission_id="$(plutil -extract id raw -o - "$result" 2>/dev/null || true)"
  if [[ ! "$submission_id" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]]; then
    submission_id=unavailable
  fi
  printf 'Apple notarization failed: command_exit=%s status=%s id=%s\n' "$command_exit" "$status" "$submission_id" >&2
  if [[ "$submission_id" != unavailable ]]; then
    diagnostic="$work_dir/notary-$2-log.json"
    if xcrun notarytool log "$submission_id" \
      --keychain-profile "$MACOS_NOTARIZATION_PROFILE" --keychain "$MACOS_KEYCHAIN" \
      "$diagnostic" >/dev/null; then
      summary="$(plutil -extract statusSummary raw -o - "$diagnostic" 2>/dev/null || true)"
      issues="$(plutil -extract issues json -o - "$diagnostic" 2>/dev/null || true)"
      [[ -z "$summary" ]] || printf 'Apple status: %s\n' "$summary" >&2
      [[ -z "$issues" ]] || printf 'Apple validation issues: %s\n' "$issues" >&2
    else
      echo 'Apple validation log is not yet available; retain the submission ID above.' >&2
    fi
  fi
  fail 'Apple notarization must be Accepted before packaging.'
}

if [[ "$mode" == release ]]; then
  ditto -c -k --sequesterRsrc --keepParent "$app" "$work_dir/app.zip"
  notarize "$work_dir/app.zip" app
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  spctl --assess --type execute --verbose=4 "$app"
fi

ditto "$app" "$work_dir/dmg-root/$(basename "$app")"
ln -s /Applications "$work_dir/dmg-root/Applications"
dmg="$work_dir/$filename"
hdiutil create -volname DuckMusic -srcfolder "$work_dir/dmg-root" -format UDZO "$dmg"
hdiutil verify "$dmg"

if [[ "$mode" == release ]]; then
  codesign --force --timestamp --sign "$MACOS_SIGNING_IDENTITY" --keychain "$MACOS_KEYCHAIN" "$dmg"
  notarize "$dmg" dmg
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
  codesign --verify --strict --verbose=2 "$dmg"
  spctl --assess --type open --context context:primary-signature --verbose=4 "$dmg"
fi

# Assess what users actually copy from the DMG, not only the pre-package app.
mounted=true
hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$mountpoint" "$dmg"
mounted_app="$mountpoint/$(basename "$app")"
bash "$script_dir/verify_macos_app.sh" "$mounted_app" "$arch" "$version" "$build_number" "$mode"
if [[ "$mode" == release ]]; then
  xcrun stapler validate "$mounted_app"
  spctl --assess --type execute --verbose=4 "$mounted_app"
fi
hdiutil detach "$mountpoint"
mounted=false
mkdir -p "$output_dir"
ditto "$dmg" "$output_dir/$filename"
printf 'Created verified %s package: %s/%s\n' "$mode" "$output_dir" "$filename"
