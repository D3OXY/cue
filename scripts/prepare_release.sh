#!/bin/sh
# Folds pending changesets into CHANGELOG.md and deletes them.
# Prints the new version (e.g. "0.2.0"). Shared by release.sh and CI.
set -eu
cd "$(dirname "$0")/.."

FILES=$(find .changes -name '*.md' ! -name 'README.md' | sort)
if [ -z "$FILES" ]; then
  echo "error: no pending changesets in .changes/" >&2
  exit 1
fi

BUMP=patch
if grep -hq '^major:' $FILES; then BUMP=major
elif grep -hq '^minor:' $FILES; then BUMP=minor
fi

LATEST=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo v0.0.0)
V=${LATEST#v}
MAJOR=${V%%.*}
REST=${V#*.}
MINOR=${REST%%.*}
PATCH=${REST#*.}
case $BUMP in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac
NEW="$MAJOR.$MINOR.$PATCH"

SECTION=$(mktemp)
{
  echo "## v$NEW — $(date +%Y-%m-%d)"
  echo
  for f in $FILES; do
    sed -E '1s/^(major|minor|patch): */- /' "$f"
  done
  echo
} > "$SECTION"

NEWLOG=$(mktemp)
printf '# Changelog\n\n' > "$NEWLOG"
cat "$SECTION" >> "$NEWLOG"
[ -f CHANGELOG.md ] && tail -n +3 CHANGELOG.md >> "$NEWLOG"
mv "$NEWLOG" CHANGELOG.md
rm "$SECTION" $FILES

echo "$NEW"
