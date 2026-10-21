import QtQuick
import org.kde.kirigami as Kirigami
import "Theme.js" as T

Rectangle {
    id: btn
    property alias source: icon.source
    signal clicked()
    implicitWidth: 32
    implicitHeight: 32
    radius: 8
    color: ma.containsMouse ? T.hover : "transparent"
    border.color: T.line
    Kirigami.Icon {
        id: icon
        anchors.centerIn: parent
        width: 16; height: 16
        isMask: true
        color: ma.containsMouse ? T.text : T.soft
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }
}
