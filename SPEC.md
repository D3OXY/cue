# Cue — Spec

Open-source, macOS-only alternative to Copper (shadcn.com/copper): a quick-capture
scratchpad that merges a to-do list, clipboard, and prompt stash for AI-heavy
workflows. Lives at `github.com/D3OXY/cue`. MIT.

## Product

One surface: a full-height **Liquid Glass side sheet** that slides in from the right
edge, Notification Center-style. Capture text and files from anywhere, keep them as
checkable items grouped into sections, route them back out to AI tools with ⌘C.
Everything lives in one local SQLite file. No accounts, no cloud, no telemetry.

### Summoning (three ways, one sheet)

1. **Double-tap Shift** (hardcoded v1; configurable hotkey is a named v1.1 item).
   With an active text selection this captures instantly instead (see below).
2. **Two-finger swipe from the right trackpad edge** — opt-in. Cue reads raw trackpad
   touches via the private `MultitouchSupport` framework (the BetterTouchTool/Swish
   technique); the enable flow deep-links the user to System Settings ▸ Trackpad to
   turn off the Notification Center gesture first. Private API: may break on a macOS
   update, so it is never the only way in and degrades to a no-op.
3. **Status item** click.

Esc / double-Shift / click-away dismisses — unless **pinned**: a pin toggle keeps the
sheet open (docked narrow next to an agent app is the core workflow). This is the
"opened app" mode; there is no separate window.

### Sheet layout (top to bottom)

1. **Search field** — pinned at top, with ••• menu (sections, settings) beside it.
2. **Section header** — active section name + divider.
3. **Item list** — pill cards, chronological, new items append at the bottom.
   Circle checkbox; checked dims. Attachment thumbnails render in the card;
   attachment-only items allowed.
4. **Composer** — placeholder "Add a note, type a prompt, or describe a task",
   paperclip button, staged-attachment chips. Enter adds; Shift+Enter newline.

### Core behaviors

1. **Sheet** — non-activating (never steals focus), full height, right-anchored,
   slides over everything including fullscreen apps. Real Liquid Glass
   (`.glassEffect()` / `GlassEffectContainer`), not material imitation.
2. **Instant selection capture** — double-Shift while the frontmost app has a text
   selection adds it straight to the active section as a new item (flash/toast
   confirmation; sheet state untouched). AX path only (`AXSelectedText`); no
   clipboard simulation — clipboard side effects require explicit intent. Apps
   without AX text support simply don't capture. No selection → summon + focus
   composer.
3. **Sections** — flat, no nesting. Type `# Name` in the composer to create-or-
   switch; ⌘K opens a section switcher; ••• menu lists them. Every item belongs to
   exactly one section; captures land in the **active** section, which persists
   across restarts. Default **Inbox** section, undeletable; deleting a section moves
   its items to Inbox (non-destructive).
4. **Attachments** — files/images via drag-drop onto the sheet, paste into the
   composer, or paperclip picker. Stored as **managed copies** under
   `~/Library/Application Support/Cue/attachments/` — items never dangle. "Attached
   1 file" toast on drop. FTS indexes filenames only, not contents.
5. **Copy-out / routing** — the point of the app. ⌘C on a focused item puts its text
   *and* files on the pasteboard together — one paste into Claude/Cursor/ChatGPT
   carries both. **Multi-select** (⌘-click / shift-click) + ⌘C pastes as a numbered
   list plus all attachments: queue prompts, route the batch to an agent, check off.
6. **Item actions** — arrow keys navigate, ⌘C copies (flash confirmation), ⌫ deletes
   with ⌘Z undo, drag reorders.
7. **Search** — top field, **global**: all sections + archive, live FTS5, results
   badged with their section. Search is the door to everything; the list only shows
   the room you're standing in.
8. **Retention — archive vs delete are different things.**
   - **Archive** (automatic): done items older than 7 days leave the list but keep
     everything — row, attachments, searchability. DB is the memory.
   - **Delete** (explicit ⌫): removes the item *and its attachment files from disk*.
     Because delete is undoable (⌘Z), files are removed deferred — held in a pending
     state until the undo window lapses (app quit or undo stack cleared), then
     purged. Nothing else ever deletes attachment files.

### Out of scope for v1

Sync, tags, nested sections, markdown rendering, themes, configurable hotkey (v1.1),
separate document window, voice input, Windows/Linux, App Store, Apple notarization,
brew.

## App shape

- Menu bar app (`LSUIElement = true`): status item with Open, Check for Updates,
  Settings, Quit. No Dock icon.
- Minimal Settings: edge-swipe toggle (+ guided NC-gesture-disable flow), launch at
  login. Nothing else.
- Requires Accessibility permission (Shift-Shift event tap + reading selections).
  First-run sheet explains why, deep-links to System Settings, polls for grant.
  Degrades gracefully without it (status-item open still works).

## Tech

| Concern | Choice | Why |
|---|---|---|
| Language/UI | Swift 5.10, SwiftUI + AppKit glue (NSPanel, NSStatusItem) | Hotkey/AX/gesture need native APIs regardless; wrap nothing around them |
| Min target | **macOS 26 (Tahoe)** | Real Liquid Glass APIs; one UI code path; target user runs current OS |
| Hotkey | `CGEventTap` flags-changed; double-Shift within 300ms; any intervening key cancels; tap self-re-enables after system timeout | Bare-modifier taps aren't normal hotkeys |
| Edge swipe | Private `MultitouchSupport.framework`, raw touch stream, right-edge 2-finger detection | Only way to get NC-style gesture; opt-in, isolated behind a protocol so breakage is contained |
| Selection read | `AXUIElement` focused-element `AXSelectedText` only | No silent clipboard side effects |
| Storage | SQLite via GRDB; FTS5 on item text + attachment filenames | Search is a v1 requirement; crash-safe writes free |
| Auto-update | Sparkle 2, EdDSA appcast, **silent**: daily check, install on quit; manual "Check for Updates" in status menu | Day-1 requirement |
| Update feed | `appcast.xml` on gh-pages of the same repo; zips on GitHub Releases | One repo, free |
| CI/Release | GitHub Actions: tag `v*` → xcodebuild → codesign (self-signed cert) → zip → `sign_update` → Release + appcast push | One-command releases |
| Distribution | `curl -fsSL https://raw.githubusercontent.com/D3OXY/cue/main/scripts/install.sh \| sh` (+ manual zip with documented `xattr` incantation) | CLI download avoids Gatekeeper quarantine; no brew for now |
| License | MIT | — |

### Signing posture

No Apple Developer ID. App is signed with a **stable self-signed certificate** (private
key in CI secrets) — stable code-signing identity means the Accessibility/TCC grant
survives auto-updates (ad-hoc signing would reset it every build). Gatekeeper friction
on browser downloads remains; install script is the blessed path. Sparkle verifies
update integrity via EdDSA independently of Apple. Revisit Developer ID ($99/yr) if
traction warrants.

## Data model (schema v1)

```sql
CREATE TABLE section (
  id TEXT PRIMARY KEY,        -- UUID; fixed known UUID for Inbox
  name TEXT NOT NULL UNIQUE,
  created_at REAL NOT NULL
);
CREATE TABLE item (
  id TEXT PRIMARY KEY,        -- UUID
  section_id TEXT NOT NULL REFERENCES section(id),
  text TEXT NOT NULL,         -- may be empty for attachment-only items
  done INTEGER NOT NULL DEFAULT 0,
  done_at REAL,               -- 7-day archive cutoff
  created_at REAL NOT NULL,
  sort_order INTEGER NOT NULL -- manual reorder within section
);
CREATE TABLE attachment (
  id TEXT PRIMARY KEY,        -- UUID; also the filename on disk
  item_id TEXT NOT NULL REFERENCES item(id),
  original_name TEXT NOT NULL,
  uti TEXT NOT NULL,          -- for thumbnails / pasteboard type
  created_at REAL NOT NULL
);
CREATE VIRTUAL TABLE item_fts USING fts5(text, content=item, content_rowid=rowid);
-- attachment original_name indexed via a second fts table or triggers into item_fts
```

DB at `~/Library/Application Support/Cue/cue.sqlite`; attachment blobs as files under
`…/Cue/attachments/<uuid>`. GRDB migrations from day 1.

## Repo layout

```
cue/                  # github.com/D3OXY/cue — everything in one repo
  Cue/                # app source
  Cue.xcodeproj
  scripts/            # release.sh, install.sh
  appcast/            # appcast.xml source (published via gh-pages)
  .github/workflows/  # ci.yml, release.yml
```
