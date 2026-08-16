# KeyDisp

**A keystroke visualizer for macOS** — shows the keys and mouse clicks you press, large on screen.

**[con3code.github.io/keydisp](https://con3code.github.io/keydisp/)** · 日本語のドキュメントは [README.ja.md](README.ja.md) をご覧ください。

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

KeyDisp reads keyboard input with the macOS **Input Monitoring** permission.
A setup guide appears on first launch:

1. **System Settings › Privacy & Security › Input Monitoring** → enable KeyDisp
2. If the Start button stays disabled after that, press **"Restart App"** in the
   guide — the permission takes effect after a restart

If KeyDisp is missing from the Input Monitoring list (e.g. after reinstalling), open
**Settings → Permissions** in the app and press the button there to re-register it.

When updating from v1.0.x you will need to grant Input Monitoring anew, and settings
are reset because the app's internal identifier changed.

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

## About the Mac App Store

As of v1.1.0 KeyDisp runs inside the App Sandbox (key capture uses a listen-only
event tap with the Input Monitoring permission), so it technically meets App Store
requirements. An App Store release is in preparation; for now KeyDisp is
distributed directly from GitHub.

## Privacy

KeyDisp displays your input on screen — that is its entire job. It does **not** log,
store, or transmit anything. There is no network access in the app.

## License

[MIT](LICENSE) — © 2026 con3code
