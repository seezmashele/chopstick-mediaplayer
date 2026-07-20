# Chopstick Media Player

A Linux video player built on **libmpv** for playback and **Qt Quick (QML)** for a
custom, cross-desktop interface.

## Status

**Milestone 1 — video-on-screen proof of concept.** A Qt Quick window plays a video
file through mpv's OpenGL render API, compositing mpv's output directly into the
scene graph. Keyboard control only; custom UI comes later.

## Requirements

- Qt 6.5+ (Quick module) — developed against 6.11
- libmpv (with `mpv/render_gl.h`)
- CMake 3.21+, Ninja, a C++17 compiler

On Arch:

```bash
sudo pacman -S --needed qt6-base qt6-declarative mpv cmake ninja gcc pkgconf
```

## Build

```bash
cmake -B build -G Ninja
cmake --build build
```

## Run

```bash
./build/chopstick /path/to/video.mp4
```

## Controls

| Key | Action |
|-----|--------|
| `Space` | Play / pause |
| `←` / `→` | Seek −5s / +5s |
| `Q` | Quit |

## Architecture

- `src/mpvitem.{h,cpp}` — `MpvItem` (a `QQuickFramebufferObject`) owns the mpv
  handle and exposes `command()` / `loadFile()` to QML. A private `MpvRenderer`
  runs on the scene-graph render thread and drives mpv's OpenGL render context,
  rendering video into the item's framebuffer object. mpv's cross-thread redraw
  callback is marshalled to the GUI thread via a queued signal.
- `src/main.cpp` — pins the OpenGL RHI backend, fixes the C numeric locale for
  libmpv, and loads the QML.
- `qml/Main.qml` — window + full-bleed `MpvItem` + keyboard shortcuts.

## Roadmap

- Milestone 2: custom QML control bar (play/pause, seek slider, volume, time,
  fullscreen) overlaid on the video, auto-hiding on idle.
- Later: playlist, settings persistence, shortcut layer, themable components,
  macOS support.
