#!/bin/bash
set -euo pipefail

orbitshift_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
orbitshift_version="${1:?Usage: publish-release.sh VERSION BUILD COMMIT}"
orbitshift_number="${2:?Usage: publish-release.sh VERSION BUILD COMMIT}"
orbitshift_commit="${3:?Usage: publish-release.sh VERSION BUILD COMMIT}"
[[ "$orbitshift_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ && "$orbitshift_number" =~ ^[1-9][0-9]*$ && "$orbitshift_commit" =~ ^[0-9a-f]{40}$ ]] || exit 2
orbitshift_repo=rvrhiv/OrbitShift
orbitshift_tag="v$orbitshift_version"
orbitshift_output="$orbitshift_root/build/releases/$orbitshift_version"
cd "$orbitshift_output"
/usr/bin/shasum -a 256 -c SHA256SUMS
[[ "$(/usr/bin/xmllint --xpath 'string(/rss/channel/item/*[local-name()="version"])' appcast.xml)" == "$orbitshift_number" ]]

# Successful API reads are required. Network/auth errors must never mean "absent".
orbitshift_existing="$(gh api "repos/$orbitshift_repo/releases?per_page=100" --paginate --jq '.[].tag_name')"
if printf '%s\n' "$orbitshift_existing" | /usr/bin/grep -Fxq "$orbitshift_tag"; then
  echo 'Release already exists. Do not overwrite signed published assets.' >&2
  exit 1
fi
orbitshift_refs="$(gh api "repos/$orbitshift_repo/git/matching-refs/tags/$orbitshift_tag" --jq '.[].ref')"
if printf '%s\n' "$orbitshift_refs" | /usr/bin/grep -Fxq "refs/tags/$orbitshift_tag"; then
  echo 'Tag already exists. Review it before retrying publication.' >&2
  exit 1
fi
[[ "$(gh api "repos/$orbitshift_repo/git/ref/heads/main" --jq '.object.sha')" == "$orbitshift_commit" ]]
orbitshift_published="$(gh api "repos/$orbitshift_repo/releases?per_page=100" --paginate --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name')"
if [[ -n "$orbitshift_published" ]]; then
  orbitshift_previous="$(/usr/bin/curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
    https://github.com/rvrhiv/OrbitShift/releases/latest/download/appcast.xml \
    | /usr/bin/xmllint --xpath 'string(/rss/channel/item/*[local-name()="version"])' -)"
  [[ "$orbitshift_previous" =~ ^[1-9][0-9]{0,8}$ && "$orbitshift_number" =~ ^[1-9][0-9]{0,8}$ ]]
  if (( orbitshift_number <= orbitshift_previous )); then
    echo 'Build number must be higher than the latest published build.' >&2
    exit 1
  fi
fi
gh release create "$orbitshift_tag" --repo "$orbitshift_repo" --target "$orbitshift_commit" \
  --draft --title "OrbitShift $orbitshift_version" --notes-file "OrbitShift-$orbitshift_version.md" \
  "OrbitShift-$orbitshift_version.zip" "OrbitShift-$orbitshift_version.md" appcast.xml SHA256SUMS
gh release edit "$orbitshift_tag" --repo "$orbitshift_repo" --draft=false --latest
