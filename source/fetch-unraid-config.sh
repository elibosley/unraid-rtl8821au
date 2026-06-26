#!/bin/bash
# Resolve an Unraid release to its exact kernel release string + kernel .config,
# by pulling only the bits we need out of the official release zip:
#   release zip  ->  bzmodules (squashfs, mounted at /usr on a live system)
#                ->  src/linux-<kver>/config
#
# This is what makes the pipeline self-updating: given just an Unraid version
# (or "latest" from the release feed) we recover the kernel version and the
# config needed to build a vermagic-matching module, with no access to a box.
#
# Inputs (env):
#   UNRAID_VERSION   e.g. "7.3.1" or "latest"      (default: latest)
#   REPO             repo checkout to write into   (default: cwd)
# Outputs:
#   writes $REPO/kernel/<kver>/config
#   prints KVER=<kver> and UNRAID_VERSION=<ver>
#   appends kver / unraid_version to $GITHUB_OUTPUT when set
set -euo pipefail

UNRAID_VERSION="${UNRAID_VERSION:-latest}"
REPO="${REPO:-$(pwd)}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "::group::Resolve release zip from feed (UNRAID_VERSION=$UNRAID_VERSION)"
FEED="$(curl -fsSL --retry 3 https://releases.unraid.net/json)"
if [ "$UNRAID_VERSION" = "latest" ]; then
  UNRAID_VERSION="$(jq -r '.[0].version' <<<"$FEED")"
fi
URL="$(jq -r --arg v "$UNRAID_VERSION" '.[] | select(.version==$v) | .url' <<<"$FEED" | head -1)"
[ -n "$URL" ] && [ "$URL" != "null" ] || { echo "ERROR: no release zip for Unraid $UNRAID_VERSION"; exit 1; }
echo "Unraid $UNRAID_VERSION -> $URL"
echo "::endgroup::"

echo "::group::Download zip + extract bzmodules -> src/"
curl -fL --retry 3 -o "$WORK/u.zip" "$URL"
( cd "$WORK" && unzip -o u.zip bzmodules )
# Pull only the src/ subtree out of the squashfs (zstd-compressed).
unsquashfs -f -d "$WORK/sq" "$WORK/bzmodules" 'src' >/dev/null
echo "::endgroup::"

CFGDIR="$(echo "$WORK"/sq/src/linux-*-Unraid)"
[ -d "$CFGDIR" ] && [ -f "$CFGDIR/config" ] || {
  echo "ERROR: src/linux-*-Unraid/config not found in bzmodules"; ls -la "$WORK/sq/src" 2>/dev/null; exit 1; }

KVER="$(basename "$CFGDIR" | sed 's/^linux-//')"
DEST="$REPO/kernel/$KVER"
mkdir -p "$DEST"
cp "$CFGDIR/config" "$DEST/config"

echo "KVER=$KVER"
echo "UNRAID_VERSION=$UNRAID_VERSION"
echo "config -> kernel/$KVER/config"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "kver=$KVER" >> "$GITHUB_OUTPUT"
  echo "unraid_version=$UNRAID_VERSION" >> "$GITHUB_OUTPUT"
fi
