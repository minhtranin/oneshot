#!/usr/bin/env bash
# oneshot installer (binary, user-scoped).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/minhtranin/oneshot/master/install.sh | bash
#   ONESHOT_VERSION=v0.1.0 bash install.sh   # pin a tag
#   bash install.sh --version                # print installed version
#   bash install.sh --uninstall              # remove
#
# Installs ~/.local/bin/oneshot. No sudo. Runtime deps: GTK3, grim or
# gnome-screenshot, wl-clipboard, cairo, pango (provided by the distro).
set -euo pipefail

REPO="minhtranin/oneshot"
ASSET="oneshot-x86_64-linux"
VERSION="${ONESHOT_VERSION:-latest}"
BIN_DIR="$HOME/.local/bin"
BIN_PATH="$BIN_DIR/oneshot"

c_cyan=$'\033[1;36m'; c_red=$'\033[1;31m'; c_yellow=$'\033[1;33m'; c_reset=$'\033[0m'
log()  { printf '%s==>%s %s\n' "$c_cyan" "$c_reset" "$*"; }
warn() { printf '%swarn%s %s\n' "$c_yellow" "$c_reset" "$*"; }
err()  { printf '%serr%s  %s\n' "$c_red" "$c_reset" "$*" >&2; }
need() { command -v "$1" >/dev/null 2>&1 || { err "missing dependency: $1"; exit 1; }; }

print_version() {
    if [[ -x "$BIN_PATH" ]]; then
        # Binary does not (yet) advertise --version; report file metadata.
        local size mtime
        size=$(stat -c%s "$BIN_PATH" 2>/dev/null || echo "?")
        mtime=$(stat -c%y "$BIN_PATH" 2>/dev/null | cut -d. -f1 || echo "?")
        echo "installed: $BIN_PATH"
        echo "size:      $size bytes"
        echo "mtime:     $mtime"
    else
        echo "oneshot not installed at $BIN_PATH"
        exit 1
    fi
}

uninstall() {
    if [[ -f "$BIN_PATH" ]]; then
        rm -f "$BIN_PATH"
        log "removed $BIN_PATH"
    else
        warn "$BIN_PATH not present"
    fi
}

print_keybind_tips() {
    cat <<'TIPS'

────────────────────────────────────────────────────────────
 Bind a hotkey to launch oneshot
────────────────────────────────────────────────────────────

▸ Hyprland  (~/.config/hypr/hyprland.conf)

    bind = , Print,           exec, ~/.local/bin/oneshot
    bind = SUPER SHIFT, S,    exec, ~/.local/bin/oneshot

  Reload:  hyprctl reload

▸ niri  (~/.config/niri/config.kdl)

    binds {
        Print                  { spawn "~/.local/bin/oneshot"; }
        Mod+Shift+S            { spawn "~/.local/bin/oneshot"; }
    }

  Reload: niri picks up changes automatically on save.

▸ GNOME (Ubuntu Wayland)

    Settings → Keyboard → View and Customize Shortcuts
      → Custom Shortcuts → +
        Name:    Oneshot
        Command: /home/$USER/.local/bin/oneshot
        Shortcut: Print  (or Super+Shift+S)

  CLI alternative (single shortcut, slot custom0):

    gsettings set org.gnome.settings-daemon.plugins.media-keys \
      custom-keybindings "['/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/']"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
      name 'Oneshot'
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
      command "$HOME/.local/bin/oneshot"
    gsettings set org.gnome.settings-daemon.plugins.media-keys.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/ \
      binding 'Print'

  Note: GNOME's built-in Print key is already bound to gnome-screenshot.
  Disable it first:
    gsettings set org.gnome.shell.keybindings screenshot "[]"

────────────────────────────────────────────────────────────
TIPS
}

case "${1:-install}" in
    -V|--version|version)
        print_version
        exit 0
        ;;
    -U|--uninstall|uninstall)
        uninstall
        exit 0
        ;;
    install|"")
        ;;
    *)
        err "unknown arg: $1"
        echo "usage: $0 [install|--version|--uninstall]" >&2
        exit 2
        ;;
esac

need curl
mkdir -p "$BIN_DIR"

if [[ "$VERSION" == "latest" ]]; then
    URL="https://github.com/$REPO/releases/latest/download/$ASSET"
else
    URL="https://github.com/$REPO/releases/download/$VERSION/$ASSET"
fi

log "downloading oneshot ($VERSION) from $URL"
curl -fL --retry 3 -o "$BIN_PATH.tmp" "$URL"
chmod +x "$BIN_PATH.tmp"
mv "$BIN_PATH.tmp" "$BIN_PATH"
log "installed → $BIN_PATH"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "$BIN_DIR is not in PATH. Add to ~/.bashrc or ~/.zshrc:"
       echo "    export PATH=\"\$HOME/.local/bin:\$PATH\"" ;;
esac

# Runtime sanity hints (non-fatal).
miss=()
for cmd in grim wl-copy; do
    command -v "$cmd" >/dev/null 2>&1 || miss+=("$cmd")
done
if (( ${#miss[@]} > 0 )); then
    warn "missing helper(s): ${miss[*]} — install for full functionality"
    echo "    Arch:   sudo pacman -S grim wl-clipboard"
    echo "    Ubuntu: sudo apt install grim wl-clipboard"
fi

print_keybind_tips
log "done. Run with: oneshot"
