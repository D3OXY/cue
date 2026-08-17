# Cue — Tickets

Ordered; each ticket independently shippable/reviewable. `[dep: N]` = hard dependency.

## M0 — Skeleton

**1. Scaffold menu-bar app**
Xcode project, macOS 26 target, `LSUIElement`, status item with Open/Quit, empty
right-anchored NSPanel hosting a SwiftUI view, toggled from the status item.
MIT license, README stub. AC: app runs, sheet toggles, no Dock icon.

**2. CI build**
GitHub Actions: `xcodebuild build test` on push/PR (macOS 26 runner). AC: green on main.

## M1 — Capture core

**3. Double-Shift event tap** [dep: 1]
`CGEventTap` on flags-changed; double Shift-tap within 300ms; any intervening
key/modifier cancels. Tap self-re-enables after system timeout.
AC: works system-wide; SHIFT-heavy typing never false-triggers.

**4. Accessibility permission onboarding** [dep: 3]
`AXIsProcessTrusted` check; first-run sheet explaining why + deep-link to System
Settings; poll and proceed on grant. Graceful degradation when denied.
AC: fresh-install flow tested from clean TCC state.

**5. Liquid Glass side sheet** [dep: 1]
Full-height right-edge sheet, `.glassEffect()`/`GlassEffectContainer`, slide-in/out
animation, non-activating, over fullscreen apps (`.canJoinAllSpaces`,
`.fullScreenAuxiliary`, proper level). Layout per SPEC: search field top (+ •••
menu), section header, item list (pill cards, append-bottom), composer bottom.
Enter adds, Shift+Enter newline, Esc closes, click-away dismisses, **pin toggle**
suppresses auto-dismiss. Checkbox toggle, checked dims. In-memory only.
AC: full keyboard flow; pinned sheet stays put while working in other apps.

**6. Instant selection capture** [dep: 3, 4, 5]
Double-Shift with a frontmost-app text selection (AX `AXSelectedText` only, no
clipboard simulation) adds it directly to the active section with flash/toast; no
selection → summon + focus composer. AC: capture 4 snippets in a row from Safari
without the sheet stealing focus; no-AX apps (Electron) cleanly no-op to summon.

**7. Item actions: copy, multi-select, delete, undo, reorder** [dep: 5]
Arrow-key focus; ⌘C copies item (flash confirmation); **⌘-click/shift-click
multi-select, ⌘C → numbered list on pasteboard**; ⌫ deletes with ⌘Z undo; drag
reorders. AC: queue 4 prompts → single paste into a chat app arrives as numbered
list.

## M2 — Data, sections, attachments, search

**8. SQLite store** [dep: 5]
GRDB, schema v1 per SPEC (section + item + attachment + FTS5), migrations from
day 1, DB at `~/Library/Application Support/Cue/cue.sqlite`. Corrupt DB → move
aside `.bak`, start fresh, log. AC: kill -9 anytime loses nothing committed.

**9. Sections** [dep: 8]
`# Name` in composer creates-or-switches; ⌘K switcher; ••• menu lists sections.
Inbox default (fixed UUID, undeletable); delete moves items to Inbox; rename;
active section persists across restarts; captures land in active section.
AC: tweet-parity flow — `# Switzerland Trip`, capture, switch, capture.

**10. Attachments** [dep: 8]
Drag-drop onto sheet, paste into composer, paperclip picker. Managed copies under
`…/Cue/attachments/<uuid>`; "Attached 1 file" toast; staged chips in composer;
thumbnails in item cards (QuickLook thumbnailing); attachment-only items.
⌘C puts text + files on pasteboard together (multi-select includes all files).
Delete removes attachment files from disk — deferred until the ⌘Z undo window
lapses, then purged; archive never touches files (archive ≠ delete, per SPEC).
AC: screenshot + prompt → one paste into Claude carries both; delete → undo
restores item with working attachments.

**11. Search** [dep: 8, 9, 10]
Top search field, live FTS5 (prefix matching), **global** across all sections +
archive; results badged with section; attachment filenames indexed. Esc clears,
then closes sheet. AC: filter latency imperceptible at 10k items.

**12. Auto-archive** [dep: 8]
Done items with `done_at` older than 7 days disappear from the main list (stay in
DB, reachable via search). Runs on launch + daily. AC: list stays a scratchpad.

## M3 — Edge-swipe gesture

**13. Two-finger right-edge swipe** [dep: 5]
Opt-in via Settings. Raw touch stream from private `MultitouchSupport.framework`;
detect 2-finger swipe starting at right trackpad edge → summon sheet. Enable flow
guides user to disable the Notification Center gesture (deep-link System Settings ▸
Trackpad). Isolated behind a protocol; framework breakage degrades to silent no-op
with a Settings notice. AC: reliable on built-in + Magic Trackpad; NC no longer
intercepts when configured; zero CPU cost when disabled.

## M4 — Distribution & auto-update (day-1 requirement)

**14. Sparkle integration** [dep: 1]
Sparkle 2 via SPM, EdDSA keypair (public in Info.plist, private in GH secret),
silent mode: daily check, install on quit. "Check for Updates" in status menu.
AC: staging appcast self-updates an old build without prompting.

**15. Release pipeline** [dep: 2, 14]
`release.yml`: tag `v*` → build Release → codesign with **stable self-signed cert**
(CI secret) → zip → `sign_update` → GH Release → regenerate appcast → push gh-pages.
AC: v0.1.0 cut end-to-end from CI; TCC grant survives an update (same signing
identity across builds — verify explicitly).

**16. Install script** [dep: 15]
`curl -fsSL .../install.sh | sh` → latest release zip → /Applications, no quarantine
attr. README install section incl. unsigned-app caveats + manual `xattr` path.
No brew. AC: clean Mac → running app in under a minute.

## M5 — Polish

**17. Settings + launch at login** [dep: 5, 13]
Minimal Settings surface: edge-swipe toggle (with guided flow), `SMAppService`
launch-at-login toggle (default off). AC: settings persist; survives reboot.

**18. QA: multi-display, Spaces, fullscreen** [dep: 5, 6, 13]
Sheet appears on the active display/Space incl. over fullscreen apps; edge-swipe +
double-Shift + instant capture verified across setups. AC: checklist doc committed
with results.

**19. OSS hygiene** [dep: 15]
README (demo GIF, install, permissions rationale, private-API disclosure for the
gesture, building from source), CONTRIBUTING, issue templates.
AC: a stranger builds and runs from README alone.

## v1.1 (named, not scheduled)

- Configurable hotkey (double-Shift is JetBrains' Search Everywhere).
- Homebrew tap, if people ask.
- Apple Developer ID, if traction warrants.
