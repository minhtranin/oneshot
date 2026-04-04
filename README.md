# Oneshot

A lightweight Wayland screenshot annotation tool written in Zig. Capture your screen, select a region, annotate with lines, rectangles, or text, then copy to clipboard or save to `~/Pictures`.

## Features

- Fullscreen region selection with dark overlay
- Draw tools: Line, Rectangle, Text
- 7 color presets
- Copy to clipboard (`wl-copy`)
- Save to `~/Pictures` as PNG
- Global keyboard shortcut support

## Requirements

```bash
sudo apt install zig libgtk-3-dev libcairo2-dev libpango1.0-dev grim wl-clipboard
```

> Zig 0.14+ required. Download from [ziglang.org](https://ziglang.org/download/).

## Build

```bash
git clone https://github.com/minhtranin/oneshot.git
cd oneshot

# Development
zig build run

# Release (install to ~/.local/bin)
zig build -Doptimize=ReleaseFast
cp zig-out/bin/oneshot ~/.local/bin/
```

## Usage

Launch with `oneshot` or bind to a keyboard shortcut.

| Key | Action |
|-----|--------|
| Drag | Select region |
| `Enter` | Confirm selection / Copy to clipboard |
| `Ctrl+Enter` | Confirm selection / Save to `~/Pictures` |
| `L` | Line tool |
| `R` | Rectangle tool |
| `T` | Text tool (click to place, type, Enter to confirm) |
| `1`–`7` | Switch color (Red, Green, Blue, Yellow, Magenta, White, Black) |
| `Esc` | Cancel / Quit |

## GNOME Keyboard Shortcut

```bash
gsettings set org.gnome.settings-daemon.plugins.media-keys custom-keybindings \
  "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/oneshot/']"

gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/oneshot/ name 'Oneshot'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/oneshot/ command '/home/$USER/.local/bin/oneshot'
gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/oneshot/ binding '<Control><Alt><Shift>p'
```
