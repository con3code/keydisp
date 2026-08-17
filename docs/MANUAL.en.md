# KeyDisp User Manual

[日本語版](MANUAL.ja.md)

KeyDisp is a macOS app that displays the keys and mouse actions you press, large on screen.
This manual covers everything from installation to a full reference of every setting.

---

## Contents

1. [Installation & First Launch](#1-installation--first-launch)
2. [Basic Usage](#2-basic-usage)
3. [Reading the Key Display](#3-reading-the-key-display)
4. [Edit Display Mode](#4-edit-display-mode)
5. [Settings Reference](#5-settings-reference)
6. [Tips](#6-tips)
7. [Troubleshooting](#7-troubleshooting)
8. [FAQ](#8-faq)
9. [Uninstalling](#9-uninstalling)

---

## 1. Installation & First Launch

### Installation

1. Download the latest `KeyDisp-vX.Y.Z.zip` from
   [Releases](https://github.com/con3code/keydisp/releases) and unzip it.
2. Move `KeyDisp.app` to your `/Applications` folder and open it.

Release binaries are signed with a Developer ID certificate and notarized by Apple,
so they open without warnings.

### Granting permissions

KeyDisp needs macOS permission to read keyboard input. A setup guide appears
on first launch — follow its steps:

1. **Input Monitoring** — System Settings › Privacy & Security › Input Monitoring →
   enable KeyDisp
2. If the Start button stays disabled after that, press **"Restart App"** in the
   guide — the permission takes effect after a restart

Once the permission is in effect, the guide closes automatically and the key
display starts.

> **Tip:** if KeyDisp does not appear in the Input Monitoring list, press the
> "Open Settings" button in the guide or in the app's settings.
> This re-requests the permission and adds KeyDisp back to the list (switched off).

> **Updating from v1.0.x**: you will need to grant Input Monitoring anew, and
> settings are reset because the app's internal identifier changed.

### What happens after launch

KeyDisp is a menu bar app. After launching, a ⌨ icon appears in the menu bar —
no regular window opens. Everything is controlled from that icon.

---

## 2. Basic Usage

### The menu bar menu

Click the ⌨ icon to open the menu:

| Item | Description |
|---|---|
| Show Keys | Toggles the key display on/off (checkmark shows current state) |
| Edit Display Mode | Adjust position, size, and design while watching a live preview |
| Reset Position & Size | Returns the overlay to the bottom-left of the main screen at default size |
| Settings… | Opens the settings window (⌘,) |
| Launch at Login | Starts KeyDisp automatically when you log in |
| Show Dock Icon | Toggles the Dock icon |
| Quit KeyDisp | Quits the app (⌘Q) |

The menu bar icon itself is toggled in Settings → General, and permission status
lives in Settings → Permissions (the setup guide opens on its own when a
permission is missing).

> **The menu bar icon and Dock icon cannot both be hidden.** If you lose access,
> open KeyDisp again from Finder or Launchpad and the settings window will appear.

### Show/hide shortcut

By default, **⌥⌘K** toggles the key display. You can change this in
Settings → Shortcut.

---

## 3. Reading the Key Display

### What is displayed

With default settings, the following inputs are shown:

- **Combinations with modifiers** — ⌘C, ⌃⌥T, ⌘⇧S, etc.
- **Special keys pressed alone** — ↩ (Return), ⇥ (Tab), ⎋ (Esc), ⌫ (Delete),
  arrows, F1–F20, etc.
- **Modifier keys pressed alone** — ⌘ ⌥ ⌃ ⇧ fn, ⇪ (Caps Lock)
- **Modifier + mouse click** — e.g. ⌘ + click (shown with a cursor mark)

Ordinary typing (letters and numbers without modifiers) is **not** shown by default.
Turn on **"Show all key input"** in the settings to display it.

### Display lifecycle

1. A key stays on screen while it is held down
2. After release, it remains for the **Hold Duration**
3. It then fades away over the **Fade-out Duration**

New inputs stack up as rows (the direction is configurable). When the row limit
is exceeded, the oldest rows disappear first.

### Repeat grouping (×n)

Pressing the same key or shortcut repeatedly is grouped as a count — e.g. `⌘V ×3` —
instead of adding new rows (on by default).

- Key repeats from holding a key down (e.g. holding ⌫) are counted the same way
- Continuous typing stays on one row, and a space typed mid-sentence joins it rather than splitting it.
  In the keycap and custom image styles, reaching the right edge starts a fresh row like a typewriter
- A small bounce animation signals each increment
- If a different input comes in between, a new row is started instead

### Symbol reference

| Symbol | Key | Symbol | Key |
|---|---|---|---|
| ⌘ | Command | ↩ | Return |
| ⌥ | Option | ⇥ | Tab |
| ⌃ | Control | ⎋ | Esc |
| ⇧ | Shift | ⌫ | Delete (Backspace) |
| ⇪ | Caps Lock | ⌦ | Forward Delete (fn+Delete) |
| fn | Function | ␣ | Space |
| ↖ / ↘ | Home / End | ⇞ / ⇟ | Page Up / Page Down |

---

## 4. Edit Display Mode

Choose **Edit Display Mode** from the menu bar to adjust the display while
watching a live preview.

### What you can do

- **Move** — drag inside the dashed frame to place the overlay anywhere,
  including on another display. The position is remembered
- **Resize** — drag the **edges** of the dashed frame to change the display area
  directly. Row wrapping follows the new width
- **HUD panel** — a floating "Edit Display Mode" panel (top-right of the screen)
  lets you change style, size, rows, stack direction, colors, and background
  in real time

Sample rows (combinations, typing, ×n counts, clicks) are shown while editing
so you can see exactly how everything will look.

To finish, press **Done** in the HUD, close the panel, or choose
Edit Display Mode from the menu again.

---

## 5. Settings Reference

Open **Settings…** from the menu bar. Settings are organized into a sidebar on the left; the headings below correspond to the sidebar items (Shortcut lives inside General). Version information lives under "About KeyDisp" in the sidebar.

### Display

| Setting | Description |
|---|---|
| Show all key input | When on, ordinary typing (letters/numbers) is displayed too. When off (default), only combinations and special keys are shown |
| Group repeated keys as ×n | Groups repeated presses and key repeats into a count (default on) |
| Keep a row each time a modifier is released | Decides what happens when you release part of a combination and **hold the rest for longer than the Hold Threshold**. **On**: the combination so far stays as history and the keys still held start a new row (⌥⇧⌘ → ⇧⌘ → ⇧) — useful when the press-and-release steps are what you are teaching. **Off (default)**: no row is added; the row simply narrows to the keys still held. Either way, releasing everything sooner leaves the whole combination (⌥⇧⌘) as one row |
| Hold Threshold | How long the remaining keys must stay down to count as deliberately held (0.2–2.0 s, default 0.5) |
| Keep history while the cursor is at the top edge | Park the cursor at the top edge to pause the fade-out; move away and rows resume fading |
| Size | Scale of the key display (×0.5–×5.0) |
| Hold Duration | How long a row remains after release (0–5 s) |
| Fade-out Duration | How long the fade takes (0.1–4 s) |
| Display Rows | Maximum simultaneous rows (1–8) |
| Show newest at the top (hang-down style) | On: rows hang from the top edge (newest at top). Off: rows stack from the bottom edge (newest at bottom) |
| Row Alignment | Which way rows grow (left / center / right). Choose Right when the overlay sits on the right side of the screen |
| Drag the key display to move it | When on, grab the keys on screen to move the display area. The fade-out pauses while dragging. Clicks directly on the keys no longer reach the app beneath (empty areas click through) |
| Hide key display while the cursor is at the bottom edge | Hot-edge feature: while the cursor stays within 10 px of the bottom edge of any screen, the display is hidden and input during that time is not shown |

### Key Labels

| Setting | Description |
|---|---|
| Distinguish upper/lower case letters | When on, typed letters appear exactly as entered (reflecting Shift and Caps Lock). When off (default), letters are always uppercase |
| Arrow Keys | **Held together** (default): groups arrows only while two or more are down at once (diagonal movement). **Also consecutive**: keeps adding arrows pressed one after another (→→↓). **Off**: one row per press |
| Show modifiers in the order pressed | Off (default) uses the conventional documentation order (⌃ ⌥ ⇧ ⌘); on shows them in the order you pressed them |
| Separate keys with "+" | Shows combinations like Ctrl+Shift+S |
| Label Style | **Mac**: ⌘ ⌥ ↩ symbols / **Windows**: Ctrl, Alt, Enter… / **Mac + Windows**: combined like "⌘/Ctrl" |
| Show the symbol ⌥ produces | An ⌥ combination typed mid-sentence always joins the row as the symbol itself (Ω), regardless of this setting. Pressed on its own, it reads "⌥Z" with this off and "⌥Z → Ω" with it on. Accent marks (dead keys) appear as the mark itself |
| Add 🌐 to input-switch keys | Marks the 英数/かな (ABC/あいう) keys with a globe so they are not mistaken for typed letters |
| Show 英数/かな as ABC/あいう | Matches the key legends on newer JIS keyboards |
| Show kana input as hiragana (JIS kana layout) | **For kana-input users.** While in Japanese input mode, typed keys are shown as JIS kana layout hiragana and symbols. Leave off if you use romaji input |

**Windows label mapping:** ⌘/⌃ → Ctrl, ⌥ → Alt, ⇧ → Shift, ↩ → Enter,
⌫ → BackSpace, ⌦ → Delete, ⎋ → Esc, 英数 → 無変換, かな → 変換, and so on.
The mapping is *shortcut-equivalent*: when you press ⌘C on the Mac, Windows users in
your audience see Ctrl+C — the shortcut they should press. (If ⌃ and ⌘ are held
together, the duplicate Ctrl is shown only once.)

### Design

| Setting | Description |
|---|---|
| Key Style | Simple (text only) / Keycap (key-shaped) / Custom Image |
| Text Color | Color of the key text |
| Outline text / Outline Color | Draws a contour around the text — keeps it readable over bright content when the background is off |
| Key / Background Color | Color of keycaps or row background |
| Show Background | Toggles the background |
| Background Opacity | 0–100% |
| Custom Background Image | Image used behind rows when the Custom Image style is selected. Ready-made samples live in [Samples/Backgrounds](../Samples/Backgrounds) |

The background is stretched as a **nine-slice**: the image is cut into thirds on both
axes, the corners keep their proportions, the top and bottom edges stretch only
horizontally, the sides only vertically, and the centre fills the rest — so artwork
stays undistorted when a row grows wide or wraps. See
[Samples/Backgrounds/README.md](../Samples/Backgrounds/README.md) for tips on making
your own.

### Mouse

| Setting | Description |
|---|---|
| Show clicks / drags at the cursor | Shows a circle at the cursor on click and while a button is held. Left click = filled circle, right click = double ring |
| Highlight Color / Size | Circle color and diameter (30–120 px) |
| Include held letter keys with clicks | Shows operations like holding A while clicking as "A + cursor mark". Only letter keys held down count, so clicking while typing normally is unaffected |
| Show modifier + click in the key display | Shows e.g. ⌘ + click as a row in the key display with a cursor mark |

### Shortcut

Press the button next to "Toggle Show / Hide", then press the key combination you
want to record (esc cancels). Combinations without a modifier key cannot be recorded.

### General

| Setting | Description |
|---|---|
| Language | System Default / 日本語 / English. Takes effect immediately |
| Launch at Login | Starts KeyDisp automatically at login |
| Show Menu Bar Icon / Show Dock Icon | Icon visibility (both cannot be hidden at once) |

### Permissions

Shows the status of Input Monitoring.

- **Open System Settings** — re-requests the permission and opens System Settings.
  Also re-adds KeyDisp to the list if it is missing
- **Re-check** — verifies the permission state and restarts key capture.
  Use this when the permission shows as granted but keys are not displayed

---

## 6. Tips

- **Classrooms with mixed Mac / Windows devices** — set the label style to
  "Windows" or "Mac + Windows" so Windows users can follow along. Turning on
  the "+" separator improves readability further
- **Presentations & screencasts** — a larger size (×2–×3) with 2–3 display rows
  keeps the screen clean
- **Fast demos flooding the display** — shorten the hold and fade durations,
  reduce the row count, or rely on ×n grouping
- **Hiding temporarily** — use the ⌥⌘K shortcut, or the hot edge
  (park the cursor at the bottom of the screen) to hide without opening menus
- **Displaying near the top of the screen** — turn on "Show newest at the top
  (hang-down style)" for a natural top-anchored layout

---

## 7. Troubleshooting

### No keys are displayed

1. Check that the ⌨ icon is in the menu bar (if not, the app is not running)
2. Check that "Show Keys" is checked in the menu
3. Check Settings → Permissions: Input Monitoring should show "Granted"
4. If granted but still nothing, press **Re-check** in the Permissions section
   (this restarts key capture)
5. If that does not help, remove KeyDisp from the lists in System Settings
   (− button), then press "Open System Settings" in the app to re-add it,
   and switch it on again

### Turned Input Monitoring on, but nothing happens

The permission does **not take effect until the app restarts**. Press
"Restart App" in the setup guide, or quit KeyDisp and open it again.

### Not working after reinstalling

A stale permission entry can appear enabled while actually pointing at the old
copy of the app. Use step 5 above (remove → re-add) to fix it.

### Ordinary typing is not displayed

This is by design. Turn on "Show all key input" (Settings → Display).

### About the F7–F12 media keys

Volume, mute, playback and brightness keys are shown with their F-key labels
(F7–F12 etc.), whether pressed directly or with fn held.

### A label like "key123" appears

This is the fallback for a key code not in the mapping table — possibly a key
specific to your keyboard. Please report the number on
[Issues](https://github.com/con3code/keydisp/issues) and it will be added.

---

## 8. FAQ

**Q. Is KeyDisp on the App Store?**
A. No. The App Sandbox required by the App Store prohibits the global event tap
KeyDisp uses to observe keystrokes. This restriction applies to all keystroke
visualizers.

**Q. Does KeyDisp log or transmit my input?**
A. No. Its entire job is displaying input on screen. Nothing is stored or sent,
and the app never accesses the network.

**Q. Will my passwords be displayed?**
A. During secure input (password fields), macOS protects key event delivery,
so they are normally not displayed. For extra safety, toggle the display off
with ⌥⌘K while typing passwords.

**Q. I use romaji input and the kana display option shows wrong characters.**
A. The kana display option is only for kana-input users. macOS provides no way
to detect the input style, so leave it off if you type romaji.

---

## 9. Uninstalling

1. Choose "Quit KeyDisp" from the menu bar
2. Move `/Applications/KeyDisp.app` to the Trash
3. (Optional) Remove KeyDisp from Input Monitoring in
   System Settings › Privacy & Security
4. (Optional) Delete its container:
   `~/Library/Containers/dev.con3.KeyDisp`

---

© 2026 con3code — [MIT License](../LICENSE)
