import QtQuick
import "Theme.js" as T

// On/off switch. The owner updates `checked` in onToggled.
Rectangle {
    id: sw
    property bool checked: false
    signal toggled(bool value)
    Colours { id: pal }
    implicitWidth: 40
    implicitHeight: 22
    radius: height / 2
    color: checked ? pal.accent : T.segOn
    Behavior on color { ColorAnimation { duration: 120 } }
    Rectangle {
        width: 16; height: 16; radius: 8
        y: 3
        x: sw.checked ? sw.width - width - 3 : 3
        color: "white"
        Behavior on x { NumberAnimation { duration: 120 } }
    }
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled(!sw.checked)
    }
}
