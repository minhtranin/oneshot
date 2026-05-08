

## Requirements

- Zig 0.15+
- `grim`, `wl-clipboard`, GTK3, Cairo, Pango

```bash
sudo apt install libgtk-3-dev libcairo2-dev libpango1.0-dev grim wl-clipboard

# for arch: sudo pacman -S zig gtk3 cairo pango grim wl-clipboard
```

## Build & Install

```bash
git clone https://github.com/minhtranin/oneshot.git
cd oneshot
zig build -Doptimize=ReleaseFast
cp zig-out/bin/oneshot ~/.local/bin/
```

## Usage



| Key | Action |
|-----|--------|
| Drag | Select region |
| `Enter` | Copy to clipboard |
| `Ctrl+Enter` | Save to `~/Pictures` |
| `D` | Freehand draw |
| `L` | Line |
| `R` | Rectangle |
| `T` | Text (click to place, type, Enter to confirm) |
| `1`–`7` | Colors: Red, Green, Blue, Yellow, Magenta, White, Black |
| Right-click | Undo last annotation |
| `Esc` | Cancel / Quit |

