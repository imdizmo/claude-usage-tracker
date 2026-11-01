import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Dialogs
import "Theme.js" as T

// The app's own settings window, styled like the popup. Writes straight to the
// plasmoid configuration, so every change applies immediately.
Window {
    id: win
    property var cfg
    property string version: ""
    readonly property var levelChoices: [50, 75, 90, 100]
    readonly property var styles: ["numbers", "meters", "ring"]
    // [setting, label, default]; an empty setting means the default
    readonly property var colours: [["accentColor", "Accent", T.accent], ["okColor", "On pace", T.ok],
                                    ["warnColor", "Close", T.warn], ["badColor", "Over pace", T.bad]]

    title: "Claude Code Usage — Settings"
    width: 780
    height: 600
    minimumWidth: 640
    minimumHeight: 570
    flags: Qt.Window | Qt.FramelessWindowHint
    color: "transparent"
    Colours { id: pal }

    function hasLevel(l) { return String(cfg.alertLevels).split(",").indexOf(String(l)) >= 0 }
    function setLevel(l, on) {
        cfg.alertLevels = levelChoices.filter(x => x === l ? on : hasLevel(x)).join(",")
    }

    Shortcut { sequence: "Escape"; onActivated: win.close() }

    ColorDialog {
        id: picker
        property string key
        onAccepted: win.cfg[key] = selectedColor.toString()
    }

    // One setting: a label on the left, its control on the right.
    component SettingRow: RowLayout {
        id: srow
        property string title
        default property alias control: slot.data
        Layout.fillWidth: true
        Layout.minimumHeight: 32
        spacing: 12
        Txt { text: srow.title; size: 14; Layout.fillWidth: true }
        Item { id: slot; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height }
    }

    // A titled card of settings.
    component Group: Card {
        id: grp
        property string title
        default property alias rows: body.data
        padding: 16
        spacing: 12
        Txt { text: grp.title.toUpperCase(); font.letterSpacing: 0.6; muted: true; size: 11 }
        ColumnLayout { id: body; Layout.fillWidth: true; spacing: 10 }
    }

    // Threshold chip: on/off, accent outline when on.
    component Chip: Rectangle {
        property string label
        property bool checked: false
        signal toggled(bool value)
        implicitWidth: chipText.implicitWidth + 24
        implicitHeight: 28
        radius: height / 2
        color: checked ? pal.accentBg : "transparent"
        border.color: checked ? pal.accent : "#33353b"
        Txt { id: chipText; anchors.centerIn: parent; text: parent.label; mono: true; size: 12; font.bold: parent.checked; color: parent.checked ? pal.accentText : T.muted }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: parent.toggled(!parent.checked) }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: T.bg
        border.color: T.line

        MouseArea { anchors { left: parent.left; right: parent.right; top: parent.top } height: 60; onPressed: win.startSystemMove() }

        ColumnLayout {
            anchors { fill: parent; leftMargin: 26; rightMargin: 26; topMargin: 22; bottomMargin: 18 }
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                Txt { text: "Settings"; font.bold: true; size: 20; Layout.fillWidth: true }
                IconButton { source: "window-close"; onClicked: win.close() }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 2
                columnSpacing: 16

                ColumnLayout {
                    Layout.preferredWidth: 1   // equal halves
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 16
                    Group {
                        title: "Plan usage"
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Txt { text: "Check every"; size: 14 }
                            Segmented {
                                mono: true
                                model: ["3m", "5m", "10m", "15m", "30m"]
                                readonly property var values: [3, 5, 10, 15, 30]
                                currentIndex: values.indexOf(win.cfg.pollMinutes)
                                onActivated: i => win.cfg.pollMinutes = values[i]
                            }
                        }
                    }
                    Group {
                        title: "Notifications"
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Txt { text: "Notify when a limit reaches"; size: 14 }
                            Row {
                                spacing: 6
                                Repeater {
                                    model: win.levelChoices
                                    Chip { label: modelData + "%"; checked: win.hasLevel(modelData); onToggled: v => win.setLevel(modelData, v) }
                                }
                            }
                        }
                        Divider {}
                        SettingRow {
                            title: "When a limit resets"
                            Toggle { checked: win.cfg.notifyReset; onToggled: v => win.cfg.notifyReset = v }
                        }
                    }
                    Group {
                        title: "Colours"
                        Row {
                            spacing: 18
                            Repeater {
                                model: win.colours
                                Column {
                                    spacing: 6
                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        width: 30; height: 30; radius: 15
                                        color: win.cfg[modelData[0]] || modelData[2]
                                        border.color: swatchMa.containsMouse ? T.text : T.line
                                        border.width: 2
                                        MouseArea {
                                            id: swatchMa
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                picker.key = modelData[0]
                                                picker.selectedColor = parent.color
                                                picker.open()
                                            }
                                        }
                                    }
                                    Txt { anchors.horizontalCenter: parent.horizontalCenter; text: modelData[1]; muted: true; size: 11 }
                                }
                            }
                        }
                        Txt {
                            visible: win.colours.some(c => win.cfg[c[0]] !== "")
                            text: "Reset to defaults"
                            size: 12
                            color: resetMa.containsMouse ? pal.accentText : pal.accent
                            MouseArea {
                                id: resetMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.colours.forEach(c => win.cfg[c[0]] = "")
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.preferredWidth: 1
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignTop
                    spacing: 16
                    Group {
                        title: "Panel"
                        SettingRow {
                            title: "Style"
                            Segmented {
                                model: ["Numbers", "Meters", "Ring"]
                                currentIndex: Math.max(0, win.styles.indexOf(win.cfg.panelStyle))
                                onActivated: i => win.cfg.panelStyle = win.styles[i]
                            }
                        }
                        Divider {}
                        SettingRow {
                            title: "Show second limit"
                            Toggle { checked: win.cfg.showWeekly; onToggled: v => win.cfg.showWeekly = v }
                        }
                        Divider {}
                        SettingRow {
                            title: "Show working sessions"
                            Toggle { checked: win.cfg.showLiveInPanel; onToggled: v => win.cfg.showLiveInPanel = v }
                        }
                    }
                    Group {
                        title: "Sessions"
                        SettingRow {
                            title: "Refresh every"
                            Segmented {
                                mono: true
                                model: ["2s", "5s", "10s", "30s"]
                                readonly property var values: [2, 5, 10, 30]
                                currentIndex: values.indexOf(win.cfg.liveSeconds)
                                onActivated: i => win.cfg.liveSeconds = values[i]
                            }
                        }
                    }
                }
            }

            Divider {}
            RowLayout {
                Layout.fillWidth: true
                Txt {
                    text: "How your data is used"
                    size: 12
                    color: privacyMa.containsMouse ? pal.accentText : pal.accent
                    MouseArea {
                        id: privacyMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Qt.openUrlExternally("https://github.com/imdizmo/claude-usage-tracker#privacy")
                    }
                }
                Item { Layout.fillWidth: true }
                Txt { text: win.version ? "v" + win.version : ""; mono: true; muted: true; size: 11 }
            }
        }

        MouseArea {   // resize grip
            anchors { right: parent.right; bottom: parent.bottom }
            width: 16; height: 16
            cursorShape: Qt.SizeFDiagCursor
            onPressed: win.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
        }
    }
}
