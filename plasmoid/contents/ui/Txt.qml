import QtQuick
import org.kde.kirigami as Kirigami
import "Theme.js" as T

// Text in the app's own palette, independent of the Plasma theme. `mono` for numbers and times.
Text {
    property bool muted: false
    property bool mono: false
    property int size: 13
    color: muted ? T.muted : T.text
    font.pixelSize: size
    font.family: mono ? Kirigami.Theme.fixedWidthFont.family : Kirigami.Theme.defaultFont.family
    elide: Text.ElideRight
}
