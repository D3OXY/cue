# Cue

A quick-capture scratchpad for AI-heavy workflows — a to-do list, clipboard, and
prompt stash merged into one Liquid Glass side sheet on your Mac's right edge.
Open-source alternative to [Copper](https://shadcn.com/copper).

Queue prompts and files as they come up, then route them to your agents:
select text anywhere → double-Shift → it's captured. ⌘C an item (or several)
over ChatGPT/Claude/Cursor and paste text + attachments in one go.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/D3OXY/cue/main/scripts/install.sh | sh
```

Requires **macOS 26 (Tahoe)** or later. Updates are automatic and silent
(Sparkle, checked daily, installed on quit).

<details>
<summary>Manual install (and why the curl script is the blessed path)</summary>

Cue is not Apple-notarized (no Apple Developer account — it's signed with the
project's own stable certificate, and updates are integrity-checked via
Sparkle's EdDSA signatures). Browser-downloaded copies get quarantined by
Gatekeeper; CLI downloads don't. If you download the zip from
[Releases](https://github.com/D3OXY/cue/releases) manually, clear the
quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Cue.app
```
</details>

## Using Cue

| Action | How |
|---|---|
| Open / close the sheet | Double-tap **Shift** (or the menu bar icon) |
| Capture selected text from any app | Select text, double-tap **Shift** |
| Add a note / prompt / task | Type in the composer, **Enter** (Shift+Enter for newlines) |
| Sections | Type `# Name` to create/switch · **⌘K** switcher |
| Attach files | Drag onto the sheet · paste · paperclip |
| Copy out | Select items, **⌘C** — several items paste as a numbered list + files |
| Search everything | Top field — all sections, archive included |
| Keep the sheet open | Pin button |
| Edge swipe (optional) | Menu bar → "Edge Swipe to Open", then turn off the Notification Center gesture in System Settings → Trackpad |

Done items auto-archive after 7 days: gone from the list, still in search.
Delete (⌫, undoable with ⌘Z) is the only thing that removes data.

## Permissions & privacy

Cue asks for **Accessibility** access, used for exactly two things: detecting
the double-Shift shortcut system-wide, and reading your text selection when you
capture. Everything lives in a local SQLite file
(`~/Library/Application Support/dev.deoxy.cue/`) — no account, no sync, no
telemetry, nothing leaves your Mac.

**Private API disclosure**: the optional edge-swipe gesture reads raw trackpad
touches via the private `MultitouchSupport` framework (the same technique as
BetterTouchTool). A macOS update could break it; if that happens the toggle
simply stops working — nothing else is affected.

## Building from source

```sh
brew install xcodegen
git clone https://github.com/D3OXY/cue && cd cue
xcodegen generate
open Cue.xcodeproj
```

Debug builds use a separate bundle id (`dev.deoxy.cue-dev`) so they don't touch
your real data or permissions. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
