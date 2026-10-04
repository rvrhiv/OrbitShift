#!/bin/bash
# Stamp only the CI checkout; never commit generated release metadata to main.
set -euo pipefail

orbitshift_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
orbitshift_version="${1:?Usage: prepare-release.sh VERSION}"
orbitshift_repo=rvrhiv/OrbitShift
orbitshift_version_pattern='^(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})\.(0|[1-9][0-9]{0,8})$'
[[ $# == 1 && "$orbitshift_version" =~ $orbitshift_version_pattern ]] || {
  echo 'Use a new stable version such as 0.7.0, without a v prefix or leading zeros.' >&2
  exit 2
}
[[ "${GITHUB_ACTIONS:-}" == true && "${GITHUB_REPOSITORY:-}" == "$orbitshift_repo" && -n "${GITHUB_OUTPUT:-}" ]] || {
  echo 'Release preparation runs only in the official GitHub Actions checkout.' >&2
  exit 1
}
cd "$orbitshift_root"
orbitshift_commit="$(git rev-parse HEAD)"
[[ "$orbitshift_commit" =~ ^[0-9a-f]{40}$ ]]
[[ "$(gh api "repos/$orbitshift_repo/git/ref/heads/main" --jq '.object.sha')" == "$orbitshift_commit" ]] || {
  echo 'main changed before preparation. Start a new workflow run.' >&2
  exit 1
}

# API failures must not be mistaken for a first release or an unused tag.
orbitshift_existing="$(gh api "repos/$orbitshift_repo/releases?per_page=100" --paginate --jq '.[].tag_name')"
if printf '%s\n' "$orbitshift_existing" | /usr/bin/grep -Fxq "v$orbitshift_version"; then
  echo 'This release already exists, including possible drafts. Inspect it before retrying.' >&2
  exit 1
fi
orbitshift_refs="$(gh api "repos/$orbitshift_repo/git/matching-refs/tags/v$orbitshift_version" --jq '.[].ref')"
if printf '%s\n' "$orbitshift_refs" | /usr/bin/grep -Fxq "refs/tags/v$orbitshift_version"; then
  echo 'This tag already exists. Choose a new version.' >&2
  exit 1
fi
orbitshift_published="$(gh api "repos/$orbitshift_repo/releases?per_page=100" --paginate --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name')"
orbitshift_previous_tag=''
orbitshift_number=1
if [[ -n "$orbitshift_published" ]]; then
  orbitshift_previous_tag="$(gh api "repos/$orbitshift_repo/releases/latest" --jq '.tag_name')"
  orbitshift_previous_version="${orbitshift_previous_tag#v}"
  [[ "$orbitshift_previous_tag" == "v$orbitshift_previous_version" && "$orbitshift_previous_version" =~ $orbitshift_version_pattern ]]
  IFS=. read -r -a orbitshift_requested_parts <<< "$orbitshift_version"
  IFS=. read -r -a orbitshift_previous_parts <<< "$orbitshift_previous_version"
  orbitshift_newer=false
  for orbitshift_index in 0 1 2; do
    if (( orbitshift_requested_parts[orbitshift_index] > orbitshift_previous_parts[orbitshift_index] )); then
      orbitshift_newer=true
      break
    elif (( orbitshift_requested_parts[orbitshift_index] < orbitshift_previous_parts[orbitshift_index] )); then
      break
    fi
  done
  [[ "$orbitshift_newer" == true ]] || {
    echo "Version must be newer than $orbitshift_previous_version." >&2
    exit 1
  }

  # Read the exact published feed, not a moving latest URL. Never reset the
  # monotonic build number when metadata is missing or cannot be retrieved.
  orbitshift_feed="$(/usr/bin/curl --fail --silent --show-error --location \
    --proto '=https' --proto-redir '=https' --connect-timeout 15 --max-time 60 --retry 3 \
    "https://github.com/$orbitshift_repo/releases/download/$orbitshift_previous_tag/appcast.xml")"
  [[ "$(printf '%s' "$orbitshift_feed" | /usr/bin/xmllint --nonet --xpath 'count(/rss/channel/item)' -)" == 1 ]]
  [[ "$(printf '%s' "$orbitshift_feed" | /usr/bin/xmllint --nonet --xpath 'string(/rss/channel/item/*[local-name()="shortVersionString"])' -)" == "$orbitshift_previous_version" ]]
  orbitshift_previous_number="$(printf '%s' "$orbitshift_feed" | /usr/bin/xmllint --nonet --xpath 'string(/rss/channel/item/*[local-name()="version"])' -)"
  [[ "$orbitshift_previous_number" =~ ^[1-9][0-9]{0,8}$ ]] || {
    echo 'The previous release has an invalid build number.' >&2
    exit 1
  }
  (( orbitshift_previous_number < 999999999 )) || {
    echo 'The supported build number range is exhausted.' >&2
    exit 1
  }
  orbitshift_number=$((orbitshift_previous_number + 1))
fi

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $orbitshift_version" "$orbitshift_root/Config/App-Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $orbitshift_number" "$orbitshift_root/Config/App-Info.plist"
{
  printf 'version=%s\n' "$orbitshift_version"
  printf 'build=%s\n' "$orbitshift_number"
  printf 'commit=%s\n' "$orbitshift_commit"
  printf 'previous_tag=%s\n' "$orbitshift_previous_tag"
} >> "$GITHUB_OUTPUT"
printf 'Preparing OrbitShift %s (build %s) from main at %s\n' "$orbitshift_version" "$orbitshift_number" "$orbitshift_commit"
