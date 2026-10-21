import QtQuick
import QtQuick.Layouts
import "Theme.js" as T

// Activity tab: totals, 12 weeks of activity, and models / projects for the chosen range.
ColumnLayout {
    id: page
    property var stats: null        // fetch.py --stats output
    property int range: 1           // Today / 7 days / 30 days / All time (picked in the popup header)
    readonly property var rangeKeys: ["today", "7", "30", "all"]
    readonly property var current: stats ? stats.ranges[rangeKeys[range]] : null
    spacing: 12
    Colours { id: pal }

    Txt { visible: page.stats === null; text: "Reading Claude Code logs…"; muted: true }

    GridLayout {
        visible: page.stats !== null
        Layout.fillWidth: true
        columns: 3
        columnSpacing: 8
        Repeater {
            model: page.stats ? [["Today", page.stats.today], ["7 days", page.stats.week], ["30 days", page.stats.month]] : []
            Card {
                id: tile
                readonly property bool on: index === page.range
                Layout.preferredWidth: 1   // equal thirds
                padding: 12
                spacing: 3
                color: on ? pal.accentCard : T.card
                border.color: on ? pal.accentLine : "transparent"
                Txt { text: modelData[0].toUpperCase(); font.letterSpacing: 0.6; size: 11; color: tile.on ? pal.accentText : T.muted }
                Txt { text: modelData[1].tok; mono: true; size: 22 }
            }
        }
    }

    Card {
        visible: page.stats !== null
        spacing: 10
        RowLayout {
            Layout.fillWidth: true
            Txt { text: "12 weeks"; font.bold: true; Layout.fillWidth: true }
            Txt { text: page.stats ? page.stats.active_days + " active days" : ""; muted: true; mono: true; size: 11 }
        }
        Row {   // one column per week, Monday on top
            Layout.alignment: Qt.AlignHCenter
            spacing: 8
            Column {
                spacing: 4
                Repeater {
                    model: ["M", " ", "W", " ", "F", " ", "S"]   // blanks, not "": positioners skip zero-width items
                    Txt { text: modelData; height: 20; verticalAlignment: Text.AlignVCenter; muted: true; mono: true; size: 9 }
                }
            }
            Grid {
                rows: 7; flow: Grid.TopToBottom; spacing: 4
                Repeater {
                    model: page.stats ? page.stats.grid : []
                    Rectangle { width: 20; height: 20; radius: 4; color: pal.heat[modelData] }
                }
            }
        }
    }

    GridLayout {
        visible: page.stats !== null
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 8
        Repeater {
            model: [["Models", "models"], ["Projects", "projects"]]
            Card {
                Layout.preferredWidth: 1   // equal halves
                Layout.alignment: Qt.AlignTop
                spacing: 10
                Txt { text: modelData[0].toUpperCase(); font.letterSpacing: 0.6; muted: true; size: 11 }
                Txt { visible: rows.count === 0; text: "Nothing in this range."; muted: true; size: 12 }
                Repeater {
                    id: rows
                    model: page.current ? page.current[modelData[1]].slice(0, 4) : []
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6
                            Txt { text: modelData.name; font.bold: true; size: 12; Layout.fillWidth: true }
                            Txt { text: modelData.tok; mono: true; size: 12 }
                            Txt { text: "· " + modelData.pct + "%"; muted: true; mono: true; size: 12 }
                        }
                        Bar { Layout.fillWidth: true; implicitHeight: 4; value: modelData.pct; fill: T.soft }
                    }
                }
            }
        }
    }

    Item { Layout.fillHeight: true }
}
