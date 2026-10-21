import QtQuick
import QtQuick.Layouts
import "Theme.js" as T

// Compact segmented control. The owner sets currentIndex in onActivated.
Rectangle {
    id: seg
    property var model: []
    property int currentIndex: 0
    property bool mono: false
    signal activated(int index)
    implicitHeight: 26
    implicitWidth: row.implicitWidth + 4
    radius: 7
    color: T.seg
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: 2
        spacing: 0
        Repeater {
            model: seg.model
            Rectangle {
                readonly property bool on: index === seg.currentIndex
                Layout.fillHeight: true
                Layout.fillWidth: true
                implicitWidth: label.implicitWidth + 20
                radius: 5
                color: on ? T.segOn : (ma.containsMouse ? T.hover : "transparent")
                Txt {
                    id: label
                    anchors.centerIn: parent
                    text: modelData
                    mono: seg.mono
                    muted: !parent.on
                    size: 12
                    font.bold: parent.on
                }
                MouseArea {
                    id: ma
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: seg.activated(index)
                }
            }
        }
    }
}
