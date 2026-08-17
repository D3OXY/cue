#!/bin/sh
# Manual escape hatch: cut a release directly from pending changesets, skipping
# the release PR flow. Normally you just merge the auto-created "Release" PR.
set -eu
cd "$(dirname "$0")/.."

NEW=$(sh scripts/prepare_release.sh)
git add -A
git commit -m "release v$NEW"
git tag "v$NEW"
git push origin HEAD "v$NEW"
echo "released v$NEW"
