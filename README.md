# KeyDisp

**A keystroke visualizer for macOS** — shows the keys and mouse clicks you press, large on screen.

日本語のドキュメントは [README.ja.md](README.ja.md) をご覧ください。

KeyDisp lives in your menu bar and displays keyboard input in real time. It is designed for
classrooms, training sessions, presentations, screencasts, and pair programming — anywhere
your audience needs to see exactly what you are pressing.

## Features

- **Real-time key display** — keys stay visible while held, then linger and fade out
  (hold time and fade time are adjustable)
- **Full modifier & special-key support** — ⌘ ⌥ ⌃ ⇧ fn, arrows, Tab, Return, Esc, Delete,
  F1–F20, and all their combinations. Function keys pressed without fn (Mission Control,
  brightness, etc.) are shown with their F-key number
- **Repeat counter** — pressing the same key or shortcut repeatedly (or holding it down)
  is grouped as `⌘V ×3` with a pulse animation instead of flooding the screen
- **Mouse visualization** — a circle highlights the cursor while clicking or dragging
  (left / right buttons look different; color and size adjustable). Modifier + click
  combinations also appear in the key display with a cursor mark
- **Windows-friendly labels** — switch key labels between Mac symbols, Windows names
  (⌘/⌃ → Ctrl, ⌥ → Alt, ↩ → Enter, ⌫ → BackSpace…), or both combined (`⌘/Ctrl`).
  Great for mixed Mac/Windows audiences
- **Japanese keyboard support** — 英数/かな keys (optionally shown as ABC/あいう to match
  newer JIS keycaps, with an optional 🌐 mark), and an optional JIS kana layout mode that
  shows typed keys as hiragana for kana-input users
- **Flexible layout** — drag the overlay anywhere on any display, resize it directly by
  dragging its edges in Edit Display Mode, choose stack direction (newest at bottom or top),
  and set the number of visible rows. Long rows wrap automatically
- **Three visual styles** — simple text, keycap look, or your own background image;
  text color, background color, and opacity are all adjustable
- **Edit Display Mode** — a floating HUD lets you tune size, colors, rows, and style while
  watching a live preview
- **Hot edge** — park the cursor at the bottom edge of the screen to temporarily hide the
  display (input is not shown while hidden)
- **Global shortcut** — toggle the display with a customizable hotkey (default ⌥⌘K)
- **English / Japanese UI** — follows the system language, or set it manually
- Launch at login, menu bar / Dock icon visibility options, and a first-launch guide for
  granting the required permissions

## Installation

1. Download the latest `KeyDisp-vX.Y.Z.zip` from [Releases](../../releases) and unzip it.
2. Move `KeyDisp.app` to your `/Applications` folder and open it.

Release binaries are signed with a Developer ID certificate and notarized by Apple,
so they open without Gatekeeper warnings.

For detailed usage instructions and a full settings reference, see the
**[User Manual](docs/MANUAL.en.md)**.

### First launch — permissions

KeyDisp reads keyboard input through macOS accessibility APIs. A setup guide appears
on first launch:

1. **System Settings › Privacy & Security › Accessibility** → enable KeyDisp *(required)*
2. **System Settings › Privacy & Security › Input Monitoring** → enable KeyDisp if it
   is listed there

Accessibility is the permission that matters. Input Monitoring often does not list
KeyDisp at all — macOS treats Accessibility as covering it — and that is perfectly
normal. If keys are showing up on screen, everything is working.

If KeyDisp is missing from the Accessibility list (e.g. after reinstalling), open
**Settings → Permissions** in the app and press the buttons there to re-register it.

## Requirements

- macOS 13 Ventura or later (Apple silicon & Intel)

## Building from source

Requires Xcode 15+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`):

```bash
xcodegen generate
xcodebuild -project KeyDisp.xcodeproj -scheme KeyDisp -configuration Release build
```

Or open the generated `KeyDisp.xcodeproj` in Xcode and run.

To produce a distributable zip in `dist/`:

```bash
./scripts/release.sh
```

## Why isn't this on the Mac App Store?

The App Store requires the App Sandbox, which prohibits the global event tap KeyDisp uses
to observe keystrokes. This is a platform-level restriction that affects all keystroke
visualizers, so KeyDisp is distributed directly instead.

## Privacy

KeyDisp displays your input on screen — that is its entire job. It does **not** log,
store, or transmit anything. There is no network access in the app.

## License

[MIT](LICENSE) — © 2026 con3code
