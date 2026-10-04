#!/bin/bash
set -euo pipefail

orbitshift_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
orbitshift_version="${1:?Usage: package-release.sh VERSION BUILD}"
orbitshift_number="${2:?Usage: package-release.sh VERSION BUILD}"
[[ "$orbitshift_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$orbitshift_number" =~ ^[1-9][0-9]*$ ]] || exit 2
orbitshift_app="$orbitshift_root/build/OrbitShift.app"
orbitshift_plist="$orbitshift_app/Contents/Info.plist"
orbitshift_output="$orbitshift_root/build/releases/$orbitshift_version"

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :OrbitShiftBuildFlavor' "$orbitshift_plist")" != distribution ]]; then
  echo 'Only distribution builds can be packaged. Run: bash Scripts/build-app.sh Release distribution' >&2
  exit 1
fi
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' "$orbitshift_plist")" == OrbitShift ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$orbitshift_plist")" == OrbitShift ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$orbitshift_plist")" == com.rvrhiv.OrbitShift ]]
for orbitshift_info in "$orbitshift_plist" "$orbitshift_root/Config/App-Info.plist"; do
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$orbitshift_info")" == "$orbitshift_version" ]]
  [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$orbitshift_info")" == "$orbitshift_number" ]]
done
for orbitshift_setting in SURequireSignedFeed SUVerifyUpdateBeforeExtraction; do
  [[ "$(/usr/libexec/PlistBuddy -c "Print :$orbitshift_setting" "$orbitshift_plist")" == true ]]
done
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$orbitshift_plist")" == "$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$orbitshift_root/Config/App-Info.plist")" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$orbitshift_plist")" == https://github.com/rvrhiv/OrbitShift/releases/latest/download/appcast.xml ]]
if [[ -e "$orbitshift_root/docs/releases/$orbitshift_version.md" && ! -s "$orbitshift_root/docs/releases/$orbitshift_version.md" ]]; then
  echo 'Supplied release notes must not be empty.' >&2
  exit 1
fi
/usr/bin/python3 "$orbitshift_root/Scripts/code_signing.py" "$orbitshift_app" distribution
for orbitshift_binary in "$orbitshift_app/Contents/MacOS/OrbitShift" "$orbitshift_app/Contents/Frameworks/Sparkle.framework/Sparkle"; do
  /usr/bin/lipo "$orbitshift_binary" -verify_arch arm64 x86_64
done
if [[ -e "$orbitshift_output" ]]; then
  echo 'Refusing to overwrite an existing release directory.' >&2
  exit 1
fi
mkdir -p "$orbitshift_output"
/usr/bin/ditto -c -k --keepParent --norsrc "$orbitshift_app" "$orbitshift_output/OrbitShift-$orbitshift_version.zip"
if [[ -f "$orbitshift_root/docs/releases/$orbitshift_version.md" ]]; then
  cp "$orbitshift_root/docs/releases/$orbitshift_version.md" "$orbitshift_output/OrbitShift-$orbitshift_version.md"
fi
echo "Packaged $orbitshift_version ($orbitshift_number). Signing is still required."
