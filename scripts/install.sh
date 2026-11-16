#!/usr/bin/env bash
# Installs the hotcfg CLI on a GitHub runner: picks the release archive for
# the runner's OS and architecture, checks its SHA-256 against the release's
# checksums.txt, and adds it to the PATH.
#
# Input (environment): HOTCFG_CLI_VERSION, "latest" or a version like v0.2.0.
# Output: cli-version in $GITHUB_OUTPUT.
set -euo pipefail

repo="https://github.com/hotcfg/cli"
# The oldest CLI with what the action uses: validate, --json, annotations.
min_minor=2

fail() {
  echo "::error::$1"
  exit 1
}

case "${RUNNER_OS:-}" in
  Linux) os=linux ;;
  macOS) os=darwin ;;
  *) fail "hotcfg/action supports Linux and macOS runners, not ${RUNNER_OS:-unknown}" ;;
esac
case "${RUNNER_ARCH:-}" in
  X64) arch=amd64 ;;
  ARM64) arch=arm64 ;;
  *) fail "No hotcfg CLI build for runner architecture ${RUNNER_ARCH:-unknown}" ;;
esac

version="${HOTCFG_CLI_VERSION:-latest}"
if [ -z "$version" ] || [ "$version" = latest ]; then
  # Follow the /releases/latest redirect: no API call, no rate limit.
  url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' --retry 3 "$repo/releases/latest")"
  version="${url##*/}"
fi
case "$version" in v*) ;; *) version="v$version" ;; esac
if ! [[ "$version" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)([-.+][0-9A-Za-z.+-]+)?$ ]]; then
  fail "Invalid hotcfg CLI version: $version"
fi
if [ "${BASH_REMATCH[1]}" -eq 0 ] && [ "${BASH_REMATCH[2]}" -lt "$min_minor" ]; then
  fail "hotcfg/action needs hotcfg CLI v0.$min_minor.0 or later, not $version"
fi

archive="hotcfg_${version#v}_${os}_${arch}.tar.gz"
dir="${RUNNER_TEMP:?}/hotcfg-cli-$version"
mkdir -p "$dir/download" "$dir/bin"
cd "$dir/download"
echo "Downloading $archive ($version)"
for f in "$archive" checksums.txt; do
  curl -fsSL --retry 3 -o "$f" "$repo/releases/download/$version/$f" ||
    fail "Could not download $f of hotcfg CLI $version: see $repo/releases"
done

expected="$(awk -v f="$archive" '$2 == f { print $1 }' checksums.txt)"
[[ "$expected" =~ ^[0-9a-f]{64}$ ]] || fail "checksums.txt of $version has no entry for $archive"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$archive" | awk '{ print $1 }')"
else
  actual="$(shasum -a 256 "$archive" | awk '{ print $1 }')"
fi
[ "$actual" = "$expected" ] || fail "SHA-256 mismatch for $archive: expected $expected, got $actual"
echo "SHA-256 verified: $actual"

tar -xzf "$archive" -C "$dir/bin" hotcfg
chmod 0755 "$dir/bin/hotcfg"
echo "$dir/bin" >> "$GITHUB_PATH"
"$dir/bin/hotcfg" version
echo "cli-version=$version" >> "$GITHUB_OUTPUT"
