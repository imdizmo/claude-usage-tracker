#!/usr/bin/env bash
# Install, update or remove Claude Code Usage Tracker for the current user. No root needed.
#
#   ./install.sh applet      install or update the KDE Plasma 6 panel widget
#   ./install.sh tray        install or update the tray widget (any desktop), start it at login
#   ./install.sh uninstall   remove both (your cached readings in ~/.cache are kept)
#   ./install.sh test        run the self-tests
#
# PYTHON=/path/to/python3 picks the interpreter (default: python3).
set -euo pipefail
cd "$(dirname "$0")"

APPLET_ID=org.dizmo.claudeusage
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/claude-usage-tracker"
BIN="$HOME/.local/bin/claude-usage-tray"
AUTOSTART="${XDG_CONFIG_HOME:-$HOME/.config}/autostart/claude-usage-tray.desktop"
PYTHON="${PYTHON:-python3}"

die() { echo "error: $*" >&2; exit 1; }

check_python() {
    command -v "$PYTHON" >/dev/null || die "$PYTHON not found. Install Python 3.11 or newer."
    "$PYTHON" -c 'import sys; sys.exit(sys.version_info < (3, 11))' \
        || die "Python 3.11 or newer is needed ($PYTHON is $("$PYTHON" -V 2>&1))."
}

applet() {
    command -v kpackagetool6 >/dev/null || die "kpackagetool6 not found. The applet needs KDE Plasma 6; use './install.sh tray' on other desktops."
    check_python
    if kpackagetool6 --type Plasma/Applet --show "$APPLET_ID" >/dev/null 2>&1; then
        kpackagetool6 --type Plasma/Applet --upgrade plasmoid >/dev/null
        echo "Applet updated. If the panel still shows the old version: systemctl --user restart plasma-plasmashell"
    else
        kpackagetool6 --type Plasma/Applet --install plasmoid >/dev/null
        echo "Applet installed. Right-click your panel, choose Add Widgets…, and drag in \"Claude Code Usage\"."
    fi
}

# The interpreter that has PySide6: the system one if it does, else a private venv.
tray_python() {
    if [ -x "$APP_DIR/venv/bin/python" ]; then
        echo "$APP_DIR/venv/bin/python"
    elif "$PYTHON" -c 'import PySide6.QtWidgets' 2>/dev/null; then
        command -v "$PYTHON"
    fi
}

tray() {
    check_python
    mkdir -p "$APP_DIR"
    local py
    py="$(tray_python)"
    if [ -z "$py" ]; then
        echo "PySide6 not found; installing it into $APP_DIR/venv (about 260 MB)…"
        "$PYTHON" -m venv "$APP_DIR/venv" || die "couldn't create a venv. Install python3-venv, or PySide6 from your distribution."
        "$APP_DIR/venv/bin/pip" install --quiet --disable-pip-version-check PySide6-Essentials
        py="$APP_DIR/venv/bin/python"
    fi
    install -m 644 usage_tray.py plasmoid/contents/code/fetch.py "$APP_DIR/"
    mkdir -p "$(dirname "$BIN")" "$(dirname "$AUTOSTART")"
    printf '#!/bin/sh\nexec "%s" "%s" "$@"\n' "$py" "$APP_DIR/usage_tray.py" > "$BIN"
    chmod 755 "$BIN"
    cat > "$AUTOSTART" <<EOF
[Desktop Entry]
Type=Application
Name=Claude Code Usage
Comment=Claude Code plan usage in the system tray
Exec=$BIN
Icon=utilities-system-monitor
X-GNOME-Autostart-enabled=true
EOF
    echo "Tray installed: it starts at login. Start it now with: claude-usage-tray &"
    case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) echo "(~/.local/bin isn't on your PATH; run $BIN instead.)" ;; esac
    if pgrep -f "$APP_DIR/usage_tray.py" >/dev/null; then
        echo "A tray from an earlier install is running; quit it from its menu and start it again to update."
    fi
}

uninstall() {
    if command -v kpackagetool6 >/dev/null && kpackagetool6 --type Plasma/Applet --show "$APPLET_ID" >/dev/null 2>&1; then
        kpackagetool6 --type Plasma/Applet --remove "$APPLET_ID" >/dev/null
        echo "Applet removed (remove it from the panel too if it's still there)."
    fi
    pkill -f "$APP_DIR/usage_tray.py" 2>/dev/null || true
    rm -rf "$APP_DIR"
    rm -f "$BIN" "$AUTOSTART"
    echo "Tray removed. Cached readings kept; delete them with: rm -f ~/.cache/claude-usage*.json"
}

selftest() {
    check_python
    "$PYTHON" plasmoid/contents/code/fetch.py --selftest
    local py
    py="$(tray_python)"
    if [ -n "$py" ]; then
        "$py" usage_tray.py --selftest
    else
        echo "Skipped the tray self-test: PySide6 can't be imported. To see why: $PYTHON -c 'import PySide6.QtWidgets'"
    fi
}

case "${1:-}" in
    applet) applet ;;
    tray) tray ;;
    uninstall) uninstall ;;
    test) selftest ;;
    *) sed -n '2,9s/^# \{0,1\}//p' "$0"; exit 2 ;;
esac
