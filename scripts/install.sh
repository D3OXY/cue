#!/bin/sh
# Cue installer: downloads the latest release into /Applications.
#   curl -fsSL https://raw.githubusercontent.com/D3OXY/cue/main/scripts/install.sh | sh
# CLI downloads skip Gatekeeper quarantine, which is why this is the blessed
# install path for an unsigned (non-Apple-notarized) app.
set -eu

REPO="D3OXY/cue"

ZIP_URL=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" \
  | grep -o '"browser_download_url": *"[^"]*\.zip"' | head -1 | cut -d '"' -f 4)

if [ -z "$ZIP_URL" ]; then
  echo "error: no release found for ${REPO}" >&2
  exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "Downloading ${ZIP_URL}…"
curl -fsSL "$ZIP_URL" -o "$TMP/cue.zip"
ditto -xk "$TMP/cue.zip" "$TMP"

if [ ! -d "$TMP/Cue.app" ]; then
  echo "error: Cue.app not found in release archive" >&2
  exit 1
fi

rm -rf /Applications/Cue.app
ditto "$TMP/Cue.app" /Applications/Cue.app
xattr -dr com.apple.quarantine /Applications/Cue.app 2>/dev/null || true

echo "Installed → /Applications/Cue.app"
open /Applications/Cue.app
