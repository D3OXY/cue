# QA checklist

Run before releases that touch windowing, capture, or gestures.
Last full pass: _pending_ (v0.2.x verified items marked).

## Summon & dismiss
- [x] Double-Shift toggles the sheet (verified v0.1.x)
- [x] Double-Shift with a selection captures instantly, toast at bottom-center (v0.1.x)
- [x] Edge swipe in opens; two-finger rightward swipe closes (v0.2.1)
- [x] Esc clears search → then closes; click-away closes; pin blocks both (v0.1.x)
- [ ] SHIFT-heavy typing (e.g. writing CAPS) never false-triggers

## Multi-display / Spaces / fullscreen
- [ ] Sheet appears on the display the cursor is on, both directions
- [ ] Sheet slides over a fullscreen app (Safari fullscreen, video)
- [ ] Sheet appears on the active Space after switching Spaces
- [ ] Toast appears on the cursor's display
- [ ] Edge swipe works on built-in trackpad and Magic Trackpad

## Capture & data
- [x] Selection capture works in Safari, Notes, Terminal (v0.1.x)
- [x] Electron apps (no AX text): double-Shift falls through to toggle (v0.1.x)
- [ ] kill -9 during rapid adds loses nothing committed
- [x] Delete → ⌘Z restores items with working attachments (v0.1.x)
- [ ] Archived item (done > 7 days) leaves list, still found via search

## Updates & install
- [x] install.sh → running app in under a minute, no Gatekeeper prompt (v0.1.2)
- [x] Release cert identity stable across releases — TCC grant survives (v0.1.2 → v0.2.x)
- [ ] Silent auto-update: old version updates on quit without any prompt
