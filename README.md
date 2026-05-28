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
ONESHOT_VERSION=v29.5.26 bash <(curl -fsSL https://raw.githubusercontent.com/minhtranin/oneshot/master/install.sh)
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

GTK3, Cairo, Pango, plus at least one screen-capture helper:

```bash
# Arch
sudo pacman -S gtk3 cairo pango grim wl-clipboard

# Ubuntu / Debian
sudo apt install libgtk-3-0 libcairo2 libpango-1.0-0 grim wl-clipboard
```

`grim` (wlroots) or `gnome-screenshot` (GNOME) must be available; the app
falls back through `xdg-desktop-portal` → `grim` → `gnome-screenshot`.

## Build from source

Requires **Zig 0.15.1** exactly (newer 0.16 has breaking std changes).

```bash
# Get Zig 0.15.1
curl -L https://ziglang.org/download/0.15.1/zig-x86_64-linux-0.15.1.tar.xz | tar xJ
mv zig-x86_64-linux-0.15.1 ~/.local/zig-0.15.1

# Build
git clone https://github.com/minhtranin/oneshot.git
cd oneshot
~/.local/zig-0.15.1/zig build -Doptimize=ReleaseFast
cp zig-out/bin/oneshot ~/.local/bin/
```

Build deps:

```bash
sudo apt install libgtk-3-dev libcairo2-dev libpango1.0-dev   # Ubuntu
sudo pacman -S gtk3 cairo pango                                # Arch
```

## Keys

- Drag — Select region
- Enter — Copy to clipboard
- Ctrl+Enter — Save to `~/Pictures`
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
