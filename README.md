# Moth

A moth that lives on your macOS desktop.

It sits above your desktop icons and below every normal window, so it rests
quietly on the wallpaper while you work. It wanders, shivers, takes off, glides
and lands on its own. Mouse events pass straight through the window unless the
cursor is actually over the moth, so it never gets in the way of anything.

Built with AppKit and SpriteKit. It runs as a menu-bar agent (`LSUIElement`),
so there is no dock icon and no window chrome.

## Species

Three, each with its own set of hand-drawn sprite frames:

| Species | Sprite prefix |
| --- | --- |
| Rosy Maple | *(none)* |
| Comet | `comet_` |
| Lime Hawk | `lime_` |

Pick one from **Select Moths…** in the menu bar, or by hovering the notch at
the top of the screen. The choice persists in `UserDefaults`.

## Menu bar

- **Select Moths…** (`⌘M`) — open the species picker
- **Fly to Base** (`⌘B`) — call the moth back to its resting spot
- **Quit Moth** (`⌘Q`)

## Animation

Each species loads nine frames by filename prefix: rest, shiver, takeoff,
landing, glide, and a five-frame wingbeat played as a ping-pong loop
(downstroke → flat → up30 → up60 → up90 and back). Flight follows a densely
sampled route that mixes smooth wandering curves with sharp darts. The sprite
carries a soft drop shadow and a diagonal sheen that sweeps across it on hover.

## Build

Requires macOS 13+ and Swift 5.9+.

```sh
swift build -c release
```

Then assemble the bundle — the binary goes in `Moth.app/Contents/MacOS/` and
all of `Assets/` is copied flat into `Moth.app/Contents/Resources/`:

```sh
mkdir -p Moth.app/Contents/MacOS Moth.app/Contents/Resources
cp .build/release/Moth Moth.app/Contents/MacOS/Moth
cp Assets/*.png Moth.app/Contents/Resources/
open Moth.app
```

`Moth.app/Contents/Info.plist` is tracked in the repo; the compiled binary and
the copied resources are not.

## Layout

```
Package.swift
Sources/Moth/
  main.swift      scene, flight behaviour, window setup, menu bar
  Picker.swift    species registry and the picker panel
Assets/           sprite frames, 33 PNGs
Moth.app/         bundle skeleton (Info.plist only)
```
