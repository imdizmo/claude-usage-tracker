import QtQuick
import QtQuick.Layouts
import "Theme.js" as T

Rectangle {
    id: card
    default property alias content: col.data
    property int padding: 14
    property alias spacing: col.spacing
    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 2 * padding
    radius: 10
    color: T.card
    ColumnLayout {
        id: col
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: card.padding }
        spacing: 6
    }
}
