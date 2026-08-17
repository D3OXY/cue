# Contributing

## Setup

```sh
brew install xcodegen
xcodegen generate      # Cue.xcodeproj is generated, not committed
open Cue.xcodeproj
```

The project targets macOS 26+, Swift 6 (strict concurrency). Debug builds run
as "Cue (Dev)" with bundle id `dev.deoxy.cue-dev` — separate data and TCC
grants from a real install.

To keep your Accessibility grant across rebuilds, sign with a stable local
certificate: create a self-signed code-signing cert named `Cue Dev` in your
login keychain (Keychain Access → Certificate Assistant → Create a
Certificate → Code Signing). `project.yml` already points at it.

## Making changes

- Keep the model small; match the style around you. Comments explain *why*,
  not *what*.
- User-facing changes need a changeset — a markdown file in `.changes/`
  (see `.changes/README.md`). CI maintains a release PR from pending
  changesets; merging it ships.
- `docs/QA.md` has the manual checklist for windowing/gesture/capture changes.

## Releases

Maintainers merge the auto-created "Release vX.Y.Z" PR. That's the whole
process: CI tags, builds, signs, updates the appcast, and every installed copy
auto-updates.
