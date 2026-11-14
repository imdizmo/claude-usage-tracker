import QtQuick
import QtQuick.Layouts
import "Theme.js" as T

// Other tools tab: plan limits of other AI coding tools on this machine (Codex, Antigravity).
ColumnLayout {
    id: page
    property var others: null       // fetch.py --others output
    readonly property var tools: others ? others.tools : []
    spacing: 12
    Colours { id: pal }

    Txt { visible: page.others === null; text: "Looking for Codex and Antigravity…"; muted: true }

    Txt {
        visible: page.others !== null && page.tools.length === 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: "No Codex or Antigravity found on this computer."
        muted: true
    }

    Repeater {
        model: page.tools
        Card {
            readonly property var tool: modelData
            spacing: 6
            RowLayout {
                Layout.fillWidth: true
                Txt { text: tool.name; font.bold: true; size: 14; Layout.fillWidth: true }
                Txt { visible: tool.plan !== ""; text: tool.plan; muted: true; mono: true; size: 11 }
            }
            Txt { visible: tool.note !== ""; text: tool.note; muted: true; size: 12; wrapMode: Text.WordWrap; Layout.fillWidth: true }
            Repeater {
                model: tool.limits
                ColumnLayout {
                    readonly property var lv: pal.level(modelData.level)
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        Txt { text: modelData.label; size: 13; Layout.fillWidth: true }
                        Txt { text: modelData.pct + "%"; font.bold: true; mono: true; size: 13 }
                    }
                    Bar {
                        Layout.fillWidth: true
                        Layout.topMargin: 2
                        Layout.bottomMargin: 2
                        value: modelData.pct
                        forecast: modelData.forecast
                        marker: modelData.pace
                        fill: lv.fill
                        ghost: lv.ghost
                    }
                    Txt {
                        visible: text !== ""
                        text: [modelData.reset ? modelData.reset.charAt(0).toUpperCase() + modelData.reset.slice(1) : "", modelData.hint]
                              .filter(x => x).join(" · ")
                        muted: true; size: 12
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
