# Chopstick Media Player — Progress

_Last updated: 2026-07-21_

A Linux video player built on **libmpv** (playback) + **Qt Quick / QML** (custom UI).
Qt Quick was chosen because it self-renders — identical look on GNOME, KDE, and anything
else — idles at zero draw, has first-class animation, and drops cleanly into mpv's OpenGL
render API.

---

## Stack & build

| Piece | Choice |
|---|---|
| Playback | libmpv 2.5 via the **OpenGL render API** |
| UI | Qt Quick / QML 6.11, C++17 |
| Build | CMake + Ninja |
| Icons | Phosphor icon font (MIT), bundled |
| Settings | `QSettings` via the QML `Settings` type |

```bash
cmake -B build -G Ninja
cmake --build build
./build/chopstick video.mkv            # or several files — first plays, rest queue
```

---

## Done

### Core playback pipeline
- `MpvItem` (a `QQuickFramebufferObject`) owns the `mpv_handle`; a private `MpvRenderer`
  drives mpv's OpenGL render context on the scene-graph render thread and renders video
  into the item's FBO.
- mpv's cross-thread callbacks are marshalled to the GUI thread via queued signals — one
  for redraws, one for draining the event queue.
- Playback state is surfaced to QML as observable properties: position, duration, paused,
  muted, volume, fileName, video/audio codec, resolution, track counts, playlist.

### Files & playlist
- **Drag and drop** anywhere on the window — first file plays, the rest queue.
- **Multiple files on the command line**, same behaviour.
- **Playlist panel** (right side, overlay): resizable 240–720px by dragging its left edge,
  320px default, X to close, click an entry to jump to it. Current entry is highlighted with
  a play glyph; others show their index. Hidden by default.
- **Folder navigation** — open a single file and prev/next walk the neighbouring media files
  in its folder, even though they were never added to the playlist. Natural sort (`vid2`
  before `vid10`), video/audio only, stops at the ends. When a file finishes it **rolls into
  the next file automatically**. Only applies when a single file is open — a playlist you
  built explicitly is navigated normally and never overwritten.

### Control bar (bottom)
- **Seek bar** — click or drag to scrub. Handle follows the cursor directly; live previews
  are throttled keyframe seeks (200ms) with one exact seek on release, and audio is muted
  during the drag to avoid choppy playback.
- **Controls row** — previous / play-pause / next, mute toggle, volume slider (glides on
  keyboard and scroll changes, stays 1:1 while dragging).
- **Status row** — play state · video codec · resolution · audio codec, then subtitle and
  audio-track buttons showing `current/total`, then elapsed / duration.
- **Auto-hides** 3s after the last pointer movement near the bottom; only movement in the
  bottom 140px wakes it. Never hides mid-interaction (hovering the bar, or scrubbing).

### Tracks
- Subtitle and audio track counts/current parsed from mpv's `track-list`.
- Subtitles cycle **through off**; audio cycles among real tracks only and **never disables
  audio**.

### Window & input
- **Drag the video** to move the window (via the compositor's `startSystemMove` — required
  on Wayland, where an app can't set its own position).
- **Click** to play/pause, **double-click** or **Alt+Enter** for fullscreen, **Esc** to exit.
- **Scroll over the video** for volume in 5% steps.

### On-screen info
- **Info badge** (top-left) that shows either the current filename or a `vol: N` readout,
  fading out after 3s. Appears automatically when a new file starts, on volume changes, and
  on demand with `N`.

### Look
- Original **SVG logo** (two tapered chopsticks converging into a play arrow) bundled as a
  Qt resource and set as the window icon.
- Phosphor icon font bundled; all UI icons come from it.
- Single shared `uiFontSize` (13px) drives general UI text; icon sizes are deliberately
  independent.

### Settings persistence
- The playlist panel, both bar rows, and the panel width are remembered across restarts
  (`~/.config/Chopstick/Chopstick Media Player.conf`).

---

## Shortcuts

| Key | Action |
|---|---|
| `Space` / click video | Play / pause |
| `←` / `→` | Seek ∓5s |
| `↑` / `↓` / scroll | Volume ±5% |
| `PgUp` / `PgDn` | Previous / next file |
| `N` | Show filename |
| `S` / `A` | Cycle subtitle / audio track |
| `Alt+Enter` / double-click | Toggle fullscreen |
| `Esc` | Exit fullscreen |
| `Ctrl+2` | Toggle controls row |
| `Ctrl+5` | Toggle status row |
| `Ctrl+7` | Toggle playlist panel |
| `Q` | Quit |

---

## Hard-won implementation notes

Things that cost real debugging — worth not rediscovering:

- **`vo=libmpv` must be set before `mpv_initialize()`**, or mpv opens its *own* separate
  output window instead of using our render context.
- **But the render context must exist before loading a file**, or `vo=libmpv` fails with
  "no video". Fix: `MpvItem` emits `ready()` once the render context is created, and QML
  loads the startup file from that signal — not from `Component.onCompleted`.
- **GL state bracketing** — `mpv_render_context_render()` is wrapped in
  `QQuickWindow::begin/endExternalCommands()`, without which mpv's raw GL corrupts the QML
  drawn over the video.
- **`setlocale(LC_NUMERIC, "C")` after constructing `QGuiApplication`** — libmpv requires it.
- **`src/` must be in `target_include_directories`**, or Qt's generated type-registration
  file silently can't find the header and fails to compile.
- **Never paste literal Phosphor glyph characters into `.qml`** — they're Private Use Area
  codepoints that render invisibly and become impossible to edit. Use
  `String.fromCharCode(0x….)`.
- **Async volume**: `add volume` is applied by mpv asynchronously, so the volume badge
  *binds* to `player.volume` rather than formatting the number at call time — otherwise it
  displays the previous value.
- **Panel resize tracks scene coordinates**, not local ones — the drag handle moves as the
  panel resizes, so local coordinates drift mid-drag.
- **Declaration order is load-bearing**: the control bar is declared *after* the playlist
  panel so it draws over it. Don't reorder.
- **Folder stepping uses a remembered path**, not mpv's live `path` property — mpv clears
  `path` when playback ends, which is exactly when auto-advance needs to know where it was.
- **Auto-advance only chains on `MPV_END_FILE_REASON_EOF`** — errors, manual stops and
  playlist redirects also raise end-file events, and chaining on those would misbehave.

---

## Known trade-offs

- With the playlist at full height and the bar layered over it, the **bottom playlist
  entries sit behind the bar** while it's visible. The bar auto-hides and the list scrolls,
  so nothing is unreachable — a bottom inset would fix it but would reintroduce the
  bar-height coupling we deliberately removed.
- The **logo is a placeholder** — original work, but intended to be replaced.
- The panel resize allows shrinking to 240px (below the 320 default), which was a judgment
  call, not an explicit requirement.

---

## To do

### Next up
- [ ] **Fullscreen button** in the control bar (only keyboard/double-click today).
- [ ] **Open-file dialog** — files can only arrive via CLI or drag-and-drop.
- [ ] **Playlist management** — remove entries, reorder, clear.
- [ ] **Hide the mouse cursor** when idle over the video.

### Persistence (foundation is in place — one alias line per setting)
- [ ] Remember **volume**.
- [ ] Remember **window size / position**.
- [ ] Optionally resume **playback position** per file.

### Features
- [ ] **Track selection menus** — pick a specific subtitle/audio track by name or language,
      rather than cycling only.
- [ ] **Playback speed** control.
- [ ] **Shortcuts overlay** (`?` or `F1`) — the list is getting long enough to warrant one.
- [ ] Mute toggle could flash `muted` in the info badge (currently only volume changes do).

### Packaging & platform
- [ ] **`.desktop` file + icon install** so the icon appears in the KDE taskbar and app
      launcher, not just the titlebar.
- [ ] **git init + license** — deliberately skipped so far; GPLv3 is the natural fit given
      libmpv and Qt.
- [ ] **macOS support** — Linux-first for now; the wrinkle is that macOS's scene graph
      prefers Metal while mpv's render API outputs GL/Vulkan.
- [ ] Evaluate **`QQuickRhiItem`** (Qt 6.7+, RHI-native) as an alternative to
      `QQuickFramebufferObject` now that the pipeline is proven.
