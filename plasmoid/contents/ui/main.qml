import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC2
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.plasmoid
import org.kde.plasma.components as PC3
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami
import "Theme.js" as T

PlasmoidItem {
    id: root

    property var usage: null       // fetch.py output: {"limits":["weekly","fable"],"weekly":{...},"stale","updated","why"}
    property var stats: null       // fetch.py --stats output
    property var live: null        // fetch.py --live output
    property var others: null      // fetch.py --others output: Codex, Antigravity
    property string err: ""        // only set when there is nothing to show
    property real lastPoll: 0      // ms epoch of the last usage poll, for "next check in"
    property real now: Date.now()
    property int tab: 0            // Plan / Activity / Sessions / Other tools
    property int range: 1          // Activity range: Today / 7 days / 30 days / All time
    readonly property bool hasData: usage !== null
    readonly property bool stale: hasData && usage.stale === true
    readonly property var cfg: Plasmoid.configuration
    // limits shown in the panel: the plan's first one (5h, or weekly on verified Ultra), plus the next if enabled
    readonly property var shown: hasData ? usage.limits.slice(0, cfg.showWeekly ? 2 : 1) : ["weekly"]
    // panel groups, one per tool switched on in Settings → Panel: {tag, items: [{short, pct, level, pace}]}
    readonly property var groups: {
        var g = []
        if (cfg.panelClaude)
            g.push({tag: "", items: hasData ? shown.map(k => usage[k]) : [{short: "", pct: null, level: "ok", pace: null}]})
        ;(others ? others.tools : []).forEach(t => {
            if (!t.limits.length || !cfg["panel" + t.name]) return
            g.push({tag: t.short, items: t.name === "Antigravity"
                ? [t.limits.reduce((a, b) => b.pct > a.pct ? b : a)]   // one number: the most-used model's quota
                : t.limits.slice(0, cfg.showWeekly ? 2 : 1)})
        })
        return g
    }
    // executable engine wants a filesystem path, not a file:// URL
    readonly property string script: Qt.resolvedUrl("../code/fetch.py").toString().replace("file://", "")
    // alert levels end up in a shell command: keep digits and commas only
    readonly property string cmd: "python3 " + script + " --alerts '" + cfg.alertLevels.replace(/[^0-9,]/g, "") + "'"
                                  + (cfg.notifyReset ? "" : " --no-reset-alert")
    readonly property string statsCmd: "python3 " + script + " --stats"
    readonly property string liveCmd: "python3 " + script + " --live"
    readonly property string othersCmd: "python3 " + script + " --others"
    readonly property int busy: live ? live.busy : 0
    Colours { id: pal }

    function forecastText(w) {
        return w.forecast === null ? "too early to forecast" : "≈ " + w.forecast + "% by reset"
    }
    function nextCheck() {
        var s = Math.max(0, Math.round((lastPoll + cfg.pollMinutes * 60000 - now) / 1000))
        return lastPoll ? "next check in " + Math.floor(s / 60) + "m " + (s % 60) + "s" : ""
    }
    function fill(it) { return it.pct === null ? Kirigami.Theme.disabledTextColor : pal.level(it.level).fill }
    function poll() { lastPoll = Date.now(); src.connectSource(cmd); src.connectSource(statsCmd); src.connectSource(othersCmd) }
    function openSettings() {
        settings.show()
        settings.raise()
        settings.requestActivate()
    }

    preferredRepresentation: compactRepresentation
    toolTipMainText: "Claude Code usage"
    toolTipSubText: !hasData ? (err ? err : "loading…")
        : usage.limits.map(k => usage[k].label + ": " + usage[k].pct + "%  (" + usage[k].reset + ")  " + forecastText(usage[k])).join("\n")
          + (others ? others.tools.map(t => t.limits.map(l => "\n" + t.name + " " + l.label + ": " + l.pct + "%" + (l.reset ? "  (" + l.reset + ")" : "")).join("")).join("") : "")
          + (stale ? "\n(reading from " + usage.updated + " — " + usage.why + ")" : "")
          + (busy ? "\n" + busy + " Claude Code session" + (busy > 1 ? "s" : "") + " working" : "")

    // "Configure…" in the right-click menu opens our own window, not KDE's dialog
    PlasmaCore.Action {
        id: configureAction
        text: "Settings…"
        icon.name: "configure"
        onTriggered: root.openSettings()
    }
    SettingsWindow { id: settings; cfg: root.cfg; version: Plasmoid.metaData.version }

    P5Support.DataSource {
        id: src
        engine: "executable"
        connectedSources: []
        onNewData: function(source, data) {
            src.disconnectSource(source)
            var j
            try { j = JSON.parse(data["stdout"]) } catch (e) {
                if (source === root.cmd && !root.hasData) root.err = "Couldn't read fetch.py output"
                return
            }
            if (source === root.statsCmd) { root.stats = j; return }
            if (source === root.liveCmd) { root.live = j; return }
            if (source === root.othersCmd) { root.others = j; return }
            if (j.error) {                     // no cache to fall back on
                if (!root.hasData) root.err = j.error
                return
            }
            root.err = ""
            root.usage = j
        }
    }

    Component.onCompleted: {
        Plasmoid.setInternalAction("configure", configureAction)
        poll()
        src.connectSource(liveCmd)
    }
    // usage % moves over hours, and /api/oauth/usage is strictly rate-limited: minutes, not seconds
    Timer { interval: root.cfg.pollMinutes * 60000; running: true; repeat: true; onTriggered: root.poll() }
    // session status is local files only, so it can refresh often
    Timer { interval: root.cfg.liveSeconds * 1000; running: true; repeat: true; onTriggered: src.connectSource(root.liveCmd) }
    // the "next check in" countdown only needs to tick while the popup is open
    Timer { interval: 1000; running: root.expanded; repeat: true; triggeredOnStart: true; onTriggered: root.now = Date.now() }

    // ---- in-panel view: one of three styles ----
    compactRepresentation: MouseArea {
        id: compact
        // Reserve horizontal space in the panel via Layout.* (implicitWidth
        // alone is ignored, which makes the widget overlap its neighbours).
        Layout.minimumWidth: row.implicitWidth + 12
        Layout.preferredWidth: row.implicitWidth + 12
        Layout.maximumWidth: row.implicitWidth + 12
        onClicked: root.expanded = !root.expanded
        readonly property string style: root.cfg.panelStyle

        Row {
            id: row
            anchors.centerIn: parent
            spacing: 8
            opacity: root.stale ? 0.55 : 1.0   // dimmed = cached

            Kirigami.Icon {   // every tool switched off in Settings → Panel: still something to click
                visible: root.groups.length === 0
                anchors.verticalCenter: parent.verticalCenter
                width: 18; height: 18
                source: "utilities-system-monitor"
            }

            Row {   // Numbers: "5h 38  wk 61  cx 5h 0 wk 16  ag 3", each number in its pace colour
                visible: compact.style === "numbers"
                anchors.verticalCenter: parent.verticalCenter
                spacing: 12
                Repeater {
                    model: root.groups
                    Row {
                        spacing: 4
                        PC3.Label { visible: modelData.tag !== ""; text: modelData.tag; font.bold: true; opacity: 0.6 }
                        Repeater {
                            model: modelData.items
                            Row {
                                spacing: 4
                                PC3.Label { visible: modelData.short !== ""; text: modelData.short; opacity: 0.6 }
                                PC3.Label {
                                    text: modelData.pct === null ? "—" : modelData.pct
                                    font.bold: true
                                    font.family: "monospace"
                                    color: root.fill(modelData)
                                }
                            }
                        }
                    }
                }
            }

            Row {   // Meters: one or two micro bars per tool with the even-pace tick
                visible: compact.style === "meters"
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Repeater {
                    model: root.groups
                    Row {
                        readonly property var items: modelData.items
                        spacing: 6
                        PC3.Label {
                            visible: modelData.tag !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.tag; font.bold: true; opacity: 0.6; font.pixelSize: 11
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 5
                            Repeater {
                                model: items
                                Bar {
                                    width: 46; implicitHeight: 5
                                    value: modelData.pct || 0
                                    marker: modelData.pace
                                    fill: root.fill(modelData)
                                    // a tint of the panel's text colour, so the track shows on light and dark panels
                                    trackColor: Qt.rgba(Kirigami.Theme.textColor.r, Kirigami.Theme.textColor.g, Kirigami.Theme.textColor.b, 0.2)
                                }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Repeater {
                                model: items
                                PC3.Label {
                                    text: modelData.pct === null ? "—" : modelData.pct + "%"
                                    font.family: "monospace"
                                    font.pixelSize: items.length > 1 ? 10 : 13
                                }
                            }
                        }
                    }
                }
            }

            Row {   // Ring: per tool, outer ring its first limit, inner ring its second
                visible: compact.style === "ring"
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Repeater {
                    model: root.groups
                    Row {
                        readonly property var items: modelData.items
                        spacing: 5
                        PC3.Label {
                            visible: modelData.tag !== ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.tag; font.bold: true; opacity: 0.6; font.pixelSize: 11
                        }
                        Canvas {
                            width: 22; height: 22
                            anchors.verticalCenter: parent.verticalCenter
                            readonly property var sig: [items.map(i => i.pct), items.map(i => i.level), pal.levels]
                            onSigChanged: requestPaint()
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.reset()
                                ctx.lineCap = "round"
                                function arc(r, w, it) {
                                    ctx.lineWidth = w
                                    ctx.strokeStyle = T.faint
                                    ctx.beginPath(); ctx.arc(11, 11, r, 0, 2 * Math.PI); ctx.stroke()
                                    if (!it.pct) return
                                    ctx.strokeStyle = root.fill(it)
                                    ctx.beginPath(); ctx.arc(11, 11, r, -Math.PI / 2, -Math.PI / 2 + 2 * Math.PI * Math.min(it.pct, 100) / 100); ctx.stroke()
                                }
                                arc(9, 3, items[0])
                                if (items.length > 1) arc(4.5, 2.5, items[1])
                            }
                        }
                        PC3.Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: items[0].pct === null ? "—" : items[0].pct
                            font.bold: true
                            font.family: "monospace"
                            color: root.fill(items[0])
                        }
                    }
                }
            }

            Rectangle {   // busy sessions: a count, pulsing while anything works
                visible: root.cfg.showLiveInPanel && root.busy > 0
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(height, count.implicitWidth + 12); height: 16; radius: 8
                color: pal.accentBg
                PC3.Label { id: count; anchors.centerIn: parent; text: root.busy; color: pal.accentText; font.pixelSize: 11; font.family: "monospace" }
                SequentialAnimation on opacity {
                    running: parent.visible; loops: Animation.Infinite
                    NumberAnimation { to: 0.45; duration: 900 }
                    NumberAnimation { to: 1.0; duration: 900 }
                }
            }
        }
    }

    // ---- click-to-expand popup ----
    fullRepresentation: Rectangle {
        Layout.minimumWidth: 440
        Layout.minimumHeight: 720
        Layout.preferredWidth: 440
        Layout.preferredHeight: 820   // fits a plan with three limits (5h, weekly, Fable)
        color: T.bg
        radius: 10

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Txt { text: "Claude Code usage"; font.bold: true; size: 15; Layout.fillWidth: true }
                Segmented {
                    visible: root.tab === 1
                    model: ["Today", "7d", "30d", "All"]
                    currentIndex: root.range
                    onActivated: i => root.range = i
                }
                IconButton { source: "configure"; onClicked: root.openSettings() }
            }

            Item {   // tabs: underline marks the current one
                Layout.fillWidth: true
                implicitHeight: tabs.implicitHeight
                Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 1; color: T.line }
                Row {
                    id: tabs
                    spacing: 20
                    Repeater {
                        model: ["Plan", "Activity", "Sessions", "Other tools"]
                        Item {
                            id: tabItem
                            readonly property bool on: index === root.tab
                            implicitWidth: tabRow.implicitWidth
                            implicitHeight: tabRow.implicitHeight + 20
                            Row {
                                id: tabRow
                                y: 8
                                spacing: 6
                                Txt { text: modelData; size: 13; font.bold: tabItem.on; muted: !tabItem.on }
                                Rectangle {
                                    visible: index === 2 && root.busy > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(height, badge.implicitWidth + 12); height: 16; radius: 8
                                    color: pal.accentBg
                                    Txt { id: badge; anchors.centerIn: parent; text: root.busy; mono: true; size: 11; color: pal.accentText }
                                }
                            }
                            Rectangle { visible: tabItem.on; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: pal.accent }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = index }
                        }
                    }
                }
            }

            StackLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: root.tab
                Flickable {   // a plan with three limits (5h, weekly, Fable) on a short popup: scroll, don't cut the chart off
                    id: planScroll
                    clip: true
                    contentHeight: plan.height
                    boundsBehavior: Flickable.StopAtBounds
                    QQC2.ScrollBar.vertical: PC3.ScrollBar {}
                    PlanPage {
                        id: plan
                        width: planScroll.width
                        height: Math.max(implicitHeight, planScroll.height)   // when it fits, the footer stays at the bottom
                        usage: root.usage
                        err: root.err
                        nextCheck: root.expanded ? root.nextCheck() : ""
                        today: root.stats ? root.stats.today : null
                    }
                }
                ActivityPage { stats: root.stats; range: root.range }
                SessionsPage { live: root.live }
                OthersPage { others: root.others }
            }
        }
    }
}
