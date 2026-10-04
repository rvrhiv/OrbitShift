#!/bin/bash
# Only run on a trusted checkout. Do not enable shell tracing around secrets.
set +x
set -euo pipefail

orbitshift_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
orbitshift_version="${1:?Usage: sign-release.sh VERSION BUILD}"
orbitshift_number="${2:?Usage: sign-release.sh VERSION BUILD}"
[[ "$orbitshift_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$orbitshift_number" =~ ^[1-9][0-9]*$ ]] || exit 2
orbitshift_output="$orbitshift_root/build/releases/$orbitshift_version"
orbitshift_tools="$orbitshift_root/.build/artifacts/sparkle/Sparkle/bin"
orbitshift_archive="$orbitshift_output/OrbitShift-$orbitshift_version.zip"
orbitshift_feed="$orbitshift_output/appcast.xml"
[[ -f "$orbitshift_archive" && -x "$orbitshift_tools/generate_appcast" ]]
[[ -s "$orbitshift_output/OrbitShift-$orbitshift_version.md" ]] || {
  echo 'Nonempty release notes are required before signing.' >&2
  exit 1
}

orbitshift_sign() {
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$1" --ed-key-file - "${@:2}"
  else
    "$1" --account com.rvrhiv.OrbitShift.release "${@:2}"
  fi
}
if [[ "${CI:-}" == true && -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo 'The release signing secret is missing.' >&2
  exit 1
fi
orbitshift_public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$orbitshift_root/Config/App-Info.plist")"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | xcrun swift "$orbitshift_root/Scripts/verify-signing-key.swift" "$orbitshift_public_key"
else
  [[ "$("$orbitshift_tools/generate_keys" --account com.rvrhiv.OrbitShift.release -p)" == "$orbitshift_public_key" ]] || {
    echo 'OrbitShift signing key does not match the public key in the app.' >&2
    exit 1
  }
fi
orbitshift_sign "$orbitshift_tools/generate_appcast" \
  --download-url-prefix "https://github.com/rvrhiv/OrbitShift/releases/download/v$orbitshift_version/" \
  --release-notes-url-prefix "https://github.com/rvrhiv/OrbitShift/releases/download/v$orbitshift_version/" \
  --link https://github.com/rvrhiv/OrbitShift/releases \
  --maximum-deltas 0 --maximum-versions 1 "$orbitshift_output"

# Validate generated metadata and signatures before the publishing step.
[[ -f "$orbitshift_feed" ]]
[[ "$(/usr/bin/xmllint --xpath 'count(/rss/channel/item)' "$orbitshift_feed")" == 1 ]]
[[ "$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/*[local-name()="version"])' "$orbitshift_feed")" == "$orbitshift_number" ]]
[[ "$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/*[local-name()="shortVersionString"])' "$orbitshift_feed")" == "$orbitshift_version" ]]
[[ "$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/enclosure/@url)' "$orbitshift_feed")" == "https://github.com/rvrhiv/OrbitShift/releases/download/v$orbitshift_version/OrbitShift-$orbitshift_version.zip" ]]
orbitshift_signature="$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/enclosure/@*[local-name()="edSignature"])' "$orbitshift_feed")"
[[ -n "$orbitshift_signature" ]]
orbitshift_sign "$orbitshift_tools/sign_update" --verify "$orbitshift_archive" "$orbitshift_signature"
orbitshift_sign "$orbitshift_tools/sign_update" --verify "$orbitshift_feed"
cd "$orbitshift_output"
/usr/bin/shasum -a 256 "OrbitShift-$orbitshift_version.zip" "OrbitShift-$orbitshift_version.md" appcast.xml > SHA256SUMS
echo "Verified signed release: $orbitshift_version ($orbitshift_number)"
