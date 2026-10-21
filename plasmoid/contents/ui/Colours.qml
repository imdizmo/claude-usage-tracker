import QtQuick
import org.kde.plasma.plasmoid
import "Theme.js" as T

// The colours Settings → Colours can change, and the shades derived from them.
// An empty setting means the default in Theme.js.
QtObject {
    readonly property var cfg: Plasmoid.configuration
    readonly property color accent: cfg.accentColor || T.accent
    readonly property color accentText: mix("white", accent, 0.6)
    readonly property color accentBg: mix(T.bg, accent, 0.2)
    readonly property color accentCard: mix(T.card, accent, 0.05)    // highlighted card and its border
    readonly property color accentLine: mix(T.card, accent, 0.3)
    readonly property var heat: [T.track, mix(T.track, accent, 0.3), mix(T.track, accent, 0.55), mix(T.track, accent, 0.8), accentText]
    // bar fill, the faded forecast behind it, and text in that state
    readonly property var levels: ({
        ok: shades(cfg.okColor || T.ok),
        warn: shades(cfg.warnColor || T.warn),
        bad: shades(cfg.badColor || T.bad)
    })

    function mix(a, b, t) { return Qt.tint(a, Qt.alpha(b, t)) }   // t of b over a
    function shades(c) { return { fill: Qt.color(c), ghost: mix(T.card, c, 0.2), text: mix("white", c, 0.65) } }
    function level(l) { return levels[l] || levels.ok }
}
