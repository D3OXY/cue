# Changesets

Every user-facing change adds one markdown file here (any filename). First line:

```
minor: Two-finger edge swipe to summon the sheet
```

- Prefix `major:`, `minor:`, or `patch:` decides the version bump — the highest
  prefix across all pending files wins.
- Extra lines after the first are carried into the changelog as-is.

When changesets land on main, CI keeps a **"Release vX.Y.Z" PR** open with the
folded CHANGELOG. **Merging that PR ships**: CI tags the merge and runs the
release workflow. Release notes come from the changelog section.

`scripts/release.sh` is the manual escape hatch (fold + tag + push directly).
