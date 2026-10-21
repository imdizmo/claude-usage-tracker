#!/usr/bin/env python3
"""Claude Code usage tray widget: live 5h + weekly limit %.

Data comes from plasmoid/contents/code/fetch.py, shared with the Plasma applet:
it reads the OAuth token Claude Code stores in ~/.claude/.credentials.json and
falls back to the last good reading when the endpoint rate-limits.
"""
import os
import sys
import threading
from pathlib import Path

from PySide6.QtCore import Qt, QTimer, Signal
from PySide6.QtGui import QColor, QFont, QIcon, QPainter, QPixmap
from PySide6.QtWidgets import (
    QApplication, QHBoxLayout, QLabel, QMenu, QProgressBar,
    QSystemTrayIcon, QVBoxLayout, QWidget,
)

# ponytail: the plasmoid's fetcher is stdlib-only, so the tray reuses it (cache, 429 fallback, error text).
# Next to this script when installed by install.sh, else in the repo checkout.
HERE = Path(__file__).resolve().parent
FETCH_DIR = next((d for d in (HERE, HERE / "plasmoid" / "contents" / "code") if (d / "fetch.py").is_file()), None)
if FETCH_DIR is None:
    sys.exit("fetch.py not found next to usage_tray.py. Install with ./install.sh tray, or run from the repo.")
sys.dont_write_bytecode = True  # keep __pycache__ out of the applet package kpackagetool installs
sys.path.insert(0, str(FETCH_DIR))
import fetch  # noqa: E402

POLL_MS = 300_000  # 5 min: usage moves over hours, and /api/oauth/usage is rate-limited
# A cached reading younger than this (e.g. the applet's) is reused instead of a second request.
MAX_AGE = POLL_MS / 1000 - 30


def color_for(pct):
    return QColor("#3fb950") if pct < 50 else QColor("#d29922") if pct < 80 else QColor("#f85149")


def make_icon(pct):
    """Render the 5h percentage as the tray icon so it's glanceable."""
    pm = QPixmap(64, 64)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    f = QFont()
    f.setPixelSize(40 if pct < 100 else 32)
    f.setBold(True)
    p.setFont(f)
    p.setPen(color_for(pct))
    p.drawText(pm.rect(), Qt.AlignCenter, str(pct))
    p.end()
    return QIcon(pm)


MARGIN = 16  # gap from the screen edge


class Overlay(QWidget):
    """Frameless always-on-top panel pinned to a screen corner. Drag to move."""
    def __init__(self):
        super().__init__(None, Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool)
        self.setStyleSheet("QWidget{background:#161b22;color:#e6edf3;border:1px solid #30363d;}"
                           "QLabel{border:none;}"
                           "QProgressBar{background:#21262d;border:none;border-radius:4px;height:10px;}"
                           "QProgressBar::chunk{border-radius:4px;}")
        self._drag = None
        lay = QVBoxLayout(self)
        lay.setContentsMargins(14, 12, 14, 12)
        title = QLabel("Claude Code usage  ·  drag to move")
        title.setStyleSheet("font-weight:bold;color:#8b949e;")
        lay.addWidget(title)
        self.rows = {}
        for name in ("5h", "weekly"):
            row = QHBoxLayout()
            lbl = QLabel(name)
            lbl.setFixedWidth(48)
            bar = QProgressBar()
            bar.setTextVisible(False)
            bar.setFixedWidth(140)
            pct = QLabel()
            pct.setFixedWidth(36)
            pct.setAlignment(Qt.AlignRight)
            reset = QLabel()
            reset.setStyleSheet("color:#8b949e;")
            for w in (lbl, bar, pct, reset):
                row.addWidget(w)
            lay.addLayout(row)
            self.rows[name] = (bar, pct, reset)

    def update_data(self, data):
        for name, (bar, pct, reset) in self.rows.items():
            val = data[name]["pct"]
            bar.setValue(min(val, 100))
            bar.setStyleSheet(f"QProgressBar::chunk{{background:{color_for(val).name()};border-radius:4px;}}")
            pct.setText(f"{val}%")
            reset.setText(data[name]["reset"])

    def pin_corner(self):
        """Sit flush on top of the taskbar, bottom-right. availableGeometry()
        excludes the taskbar, so its bottom edge is the top of the taskbar."""
        self.adjustSize()
        area = self.screen().availableGeometry()
        self.move(area.right() - self.width() - MARGIN,
                  area.bottom() - self.height() + 1)

    def mousePressEvent(self, e):
        if e.button() == Qt.LeftButton:
            self._drag = e.globalPosition().toPoint() - self.frameGeometry().topLeft()

    def mouseMoveEvent(self, e):
        if self._drag is not None and e.buttons() & Qt.LeftButton:
            self.move(e.globalPosition().toPoint() - self._drag)

    def mouseReleaseEvent(self, e):
        self._drag = None


class Tray(QSystemTrayIcon):
    ready = Signal(object)  # emitted from the fetch thread; Qt queues it onto the GUI thread

    def __init__(self, app):
        super().__init__()
        self.app = app
        self.overlay = Overlay()
        self._pinned = False
        self._fetching = False
        self.ready.connect(self.show_data)
        menu = QMenu()
        menu.addAction("Refresh now", lambda: self.refresh(force=True))
        menu.addAction("Show/hide panel", self.toggle)
        menu.addSeparator()
        menu.addAction("Quit", app.quit)
        self.setContextMenu(menu)
        self.activated.connect(self.on_click)
        self.timer = QTimer(self)
        self.timer.timeout.connect(self.refresh)
        self.timer.start(POLL_MS)
        self.refresh()
        self.overlay.show()

    def toggle(self):
        self.overlay.setVisible(not self.overlay.isVisible())

    def on_click(self, reason):
        if reason == QSystemTrayIcon.Trigger:  # left click
            self.toggle()

    def refresh(self, force=False):
        """Fetch on a worker thread so a slow or offline request never freezes the tray."""
        if self._fetching:  # previous request still waiting on the network
            return
        self._fetching = True
        threading.Thread(target=self._work, args=(0 if force else MAX_AGE,), daemon=True).start()

    def _work(self, max_age):
        try:
            data = fetch.poll(levels=None, max_age=max_age)  # notifications are the plasmoid's job
        except Exception as e:  # full disk, malformed cache/API data
            data = {"error": f"Unexpected error: {e!r}"}
        self.ready.emit(data)

    def show_data(self, data):
        self._fetching = False
        try:
            if "error" not in data:
                self.overlay.update_data(data)  # KeyError on a partial or odd reading
        except Exception as e:  # a reading missing a window: say so, don't freeze old numbers
            data = {"error": f"Unexpected error: {e!r}"}
        if "error" in data:
            self.setIcon(make_icon(0))
            self.setToolTip(f"Claude usage unavailable: {data['error']}")
            return
        if not self._pinned:  # size is known only after first data
            self.overlay.pin_corner()
            self._pinned = True
        h, w = data["5h"], data["weekly"]
        self.setIcon(make_icon(h["pct"]))
        stale = f"\n(reading from {data['updated']} — {data['why']})" if data["stale"] else ""
        self.setToolTip(f"Claude Code\n5h: {h['pct']}%  ({h['reset']})\n"
                        f"weekly: {w['pct']}%  ({w['reset']}){stale}")


def _selftest():
    assert color_for(10).name() != color_for(85).name()  # green != red
    fetch._selftest()  # data side: parsing, reset text, poll's cache fallback


def main():
    if "--selftest" in sys.argv:
        return _selftest()
    # ponytail: XWayland so move()/stay-on-top are honored; native Wayland
    # ignores client-side window positioning. Override via QT_QPA_PLATFORM if
    # you wire up wlr-layer-shell instead.
    os.environ.setdefault("QT_QPA_PLATFORM", "xcb")
    app = QApplication(sys.argv)
    app.setQuitOnLastWindowClosed(False)
    if not QSystemTrayIcon.isSystemTrayAvailable():
        sys.exit("No system tray available on this session.")
    tray = Tray(app)
    tray.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
