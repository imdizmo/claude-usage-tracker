import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import "Theme.js" as T

// Sessions tab: running Claude Code sessions, working ones first, and what each is doing.
ColumnLayout {
    id: page
    property var live: null         // fetch.py --live output
    readonly property var sessions: live ? live.sessions : []
    readonly property var groups: [
        ["Working", sessions.filter(s => s.busy), true],
        ["Waiting for you", sessions.filter(s => !s.busy), false]
    ]
    readonly property var icons: ({
        edit: "document-edit", shell: "dialog-scripts-symbolic", read: "document-open",
        web: "globe", agents: "system-run", thinking: "chronometer",
        idle: "dialog-messages", tool: "configure"
    })
    spacing: 14
    Colours { id: pal }

    Txt { visible: page.sessions.length === 0; text: "No Claude Code sessions running."; muted: true }

    Repeater {
        model: page.groups
        ColumnLayout {
            readonly property bool working: modelData[2]
            visible: modelData[1].length > 0
            Layout.fillWidth: true
            spacing: 8
            Txt {
                text: modelData[0].toUpperCase() + " · " + modelData[1].length
                font.letterSpacing: 0.6; size: 11
                color: parent.working ? pal.accentText : T.muted
            }
            Repeater {
                model: modelData[1]
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: body.implicitHeight + 28
                    radius: 10
                    color: modelData.busy ? pal.accentCard : T.card
                    border.color: modelData.busy ? pal.accentLine : "transparent"
                    RowLayout {
                        id: body
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 14 }
                        spacing: 12
                        Rectangle {
                            Layout.alignment: Qt.AlignTop
                            implicitWidth: 34; implicitHeight: 34; radius: 8
                            color: modelData.busy ? pal.accentBg : T.track
                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: 16; height: 16
                                isMask: true
                                color: modelData.busy ? pal.accentText : T.muted
                                source: page.icons[modelData.kind] || "configure"
                            }
                            SequentialAnimation on opacity {   // working sessions breathe
                                running: modelData.busy; loops: Animation.Infinite
                                NumberAnimation { to: 0.55; duration: 900 }
                                NumberAnimation { to: 1.0; duration: 900 }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8
                                Txt { text: modelData.project; font.bold: true; size: 14; Layout.fillWidth: true }
                                Txt { text: modelData.name; muted: true; mono: true; size: 11 }
                            }
                            Txt {
                                Layout.fillWidth: true
                                text: modelData.doing.charAt(0).toUpperCase() + modelData.doing.slice(1)
                                color: modelData.busy ? T.text : T.soft
                            }
                        }
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
