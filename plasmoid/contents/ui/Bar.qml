import QtQuick
import "Theme.js" as T

// Limit bar: `value` filled, `forecast` faded behind it, `marker` a tick where even pace would be (all 0-100).
Item {
    property real value: 0
    property var forecast: null
    property var marker: null
    property color fill: T.ok
    property color ghost: T.segOn
    property color trackColor: T.track
    implicitHeight: 8
    function px(p) { return width * Math.min(Math.max(p || 0, 0), 100) / 100 }
    Rectangle { anchors.fill: parent; radius: height / 2; color: parent.trackColor }
    Rectangle {
        visible: parent.forecast !== null && parent.forecast !== undefined
        width: parent.px(parent.forecast); height: parent.height; radius: height / 2
        color: parent.ghost
    }
    Rectangle { width: parent.px(parent.value); height: parent.height; radius: height / 2; color: parent.fill }
    Rectangle {
        visible: parent.marker !== null && parent.marker !== undefined
        x: parent.px(parent.marker) - 1
        y: -4
        width: 2
        height: parent.height + 8
        radius: 1
        color: T.text
    }
}
