import QtQuick
import QtQuick.Layouts
import "Theme.js" as T

// Hairline between rows of a list inside a layout.
Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    color: T.line
}
