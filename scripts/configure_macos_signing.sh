#!/usr/bin/env bash
set +x
set -euo pipefail

fail() { printf 'macOS signing setup: %s\n' "$*" >&2; exit 1; }

# Check names only; never echo the values or enable shell tracing.
for name in MACOS_CERTIFICATE_BASE64 MACOS_CERTIFICATE_PASSWORD MACOS_SIGNING_IDENTITY MACOS_NOTARIZATION_APPLE_ID MACOS_NOTARIZATION_PASSWORD APPLE_TEAM_ID; do
  [[ -n "${!name:-}" ]] || fail "Required release credential is missing: $name"
done
[[ "$MACOS_SIGNING_IDENTITY" == 'Developer ID Application: '* ]] || fail 'A Developer ID Application identity is required.'
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || fail 'Invalid APPLE_TEAM_ID.'
[[ -d "${RUNNER_TEMP:-}" && -n "${GITHUB_ENV:-}" ]] || fail 'RUNNER_TEMP and GITHUB_ENV are required on the CI runner.'

signing_dir="$(mktemp -d "$RUNNER_TEMP/duckmusic-signing.XXXXXX")"
certificate="$signing_dir/developer-id.p12"
keychain="$signing_dir/signing.keychain-db"
keep_keychain=false
cleanup() {
  rm -f -- "$certificate"
  if [[ "$keep_keychain" != true ]]; then
    security delete-keychain "$keychain" >/dev/null 2>&1 || true
    rmdir "$signing_dir" 2>/dev/null || true
  fi
}
trap cleanup EXIT
umask 077
printf '%s' "$MACOS_CERTIFICATE_BASE64" | base64 --decode > "$certificate"
keychain_password="$(openssl rand -base64 32)"
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$certificate" -P "$MACOS_CERTIFICATE_PASSWORD" -t cert -f pkcs12 \
  -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "$keychain_password" "$keychain" >/dev/null
identities="$(security find-identity -v -p codesigning "$keychain")"
grep -Fq -- "\"${MACOS_SIGNING_IDENTITY}\"" <<< "$identities" || fail 'The configured Developer ID identity is not valid in the imported keychain.'

profile=duckmusic-notary
xcrun notarytool store-credentials "$profile" --keychain "$keychain" \
  --apple-id "$MACOS_NOTARIZATION_APPLE_ID" --password "$MACOS_NOTARIZATION_PASSWORD" \
  --team-id "$APPLE_TEAM_ID" >/dev/null
printf 'MACOS_KEYCHAIN=%s\nMACOS_NOTARIZATION_PROFILE=%s\n' "$keychain" "$profile" >> "$GITHUB_ENV"
keep_keychain=true
echo 'Developer ID and notarization credentials validated in an isolated keychain.'
