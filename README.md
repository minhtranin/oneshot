<p align="center">
  <img src="assets/oneshot.png" alt="Oneshot" width="180" />
</p>

# Oneshot

Wayland screenshot + annotate. Capture, draw, save or copy to clipboard.

## Install (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/minhtranin/oneshot/master/install.sh | bash
```

Binary lands in `~/.local/bin/oneshot`. The installer prints keybind tips
for Hyprland, niri, and GNOME (Ubuntu Wayland) at the end.

Pin a release:

```bash
ONESHOT_VERSION=v14.10.26 bash <(curl -fsSL https://raw.githubusercontent.com/minhtranin/oneshot/master/install.sh)
```

Check installed version:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/minhtranin/oneshot/master/install.sh) --version
```

Uninstall:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/minhtranin/oneshot/master/install.sh) --uninstall
```

## Runtime dependencies

GTK3, Cairo, Pango, PipeWire (preinstalled on modern desktops) and
`wl-clipboard`. On wlroots compositors (Hyprland, niri, sway) also `grim`.

```bash
# Arch
sudo pacman -S gtk3 cairo pango libpipewire wl-clipboard grim

# Ubuntu / Debian
sudo apt install libgtk-3-0 libcairo2 libpango-1.0-0 libpipewire-0.3-0 wl-clipboard
```

Capture on GNOME uses the xdg-desktop-portal ScreenCast stream (one raw
frame over PipeWire, ~75 ms). The first run shows GNOME's share dialog once;
the grant is remembered in `~/.config/oneshot/portal-restore-token` (delete it
to pick another monitor). Fallbacks: portal Screenshot → `gnome-screenshot` →
`grim`. On wlroots compositors `grim` is tried first.

## Build from source

Requires **Zig 0.15.x** (0.15.2 tested; 0.16 has breaking std changes).

```bash
# Get Zig 0.15.2
curl -L https://ziglang.org/download/0.15.2/zig-x86_64-linux-0.15.2.tar.xz | tar xJ
mv zig-x86_64-linux-0.15.2 ~/.local/zig-0.15.2

# Build
git clone https://github.com/minhtranin/oneshot.git
cd oneshot
~/.local/zig-0.15.2/zig build -Doptimize=ReleaseFast
cp zig-out/bin/oneshot ~/.local/bin/
```

Build deps:

```bash
sudo apt install libgtk-3-dev libcairo2-dev libpango1.0-dev libpipewire-0.3-dev   # Ubuntu
sudo pacman -S gtk3 cairo pango libpipewire                                        # Arch
```

## Keys

- Drag — Select region, Space to confirm
- Space — Copy to clipboard
- Ctrl+Space — Save to `~/Pictures`
- D — Freehand draw
- L — Line
- R — Rectangle
- T — Text (click to place, type, Enter to confirm)
- 1–7 — Colors: Red, Green, Blue, Yellow, Magenta, White, Black
- Right-click — Undo last annotation
- Esc — Cancel / Quit

## Bind to a hotkey

Run `install.sh` and the tips block at the end shows snippets for
Hyprland, niri, and GNOME (Ubuntu Wayland).
