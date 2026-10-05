pragma ComponentBehavior: Bound
import QtQuick
import org.kde.kirigami as Kirigami

// A keyboard shortcut drawn as keycaps, one per key, in the platform's own
// spelling. `sequence` is a string ("Ctrl+Shift+S") or a StandardKey number
// (`StandardKey.Save`), such as an AtlasAction's `shortcut`. A shortcut of
// several steps ("Ctrl+K, Ctrl+C") shows the steps one after the other. With
// no sequence it has no size. Screen readers get the sequence as text.
//
//   AtlasShortcutLabel { sequence: "Ctrl+Shift+S" }
//   AtlasShortcutLabel { sequence: saveAction.shortcut }
Item {
    id: control

    property var sequence: ""

    QtObject {
        id: priv
        readonly property string readableText: AtlasShortcuts.readable(control.sequence)
        readonly property var chords: AtlasShortcuts.keys(control.sequence)
        readonly property real capHeight: Math.round(Kirigami.Units.gridUnit * 1.5)
    }

    implicitWidth: priv.chords.length > 0 ? row.implicitWidth : 0
    implicitHeight: priv.chords.length > 0 ? priv.capHeight : 0
    visible: priv.chords.length > 0

    Accessible.role: Accessible.StaticText
    Accessible.name: priv.readableText

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        // A Row follows LayoutMirroring by itself: right to left in RTL.
        spacing: Kirigami.Units.smallSpacing * 2

        Repeater {
            model: priv.chords
            delegate: Row {
                id: chord
                required property var modelData
                required property int index
                spacing: Kirigami.Units.smallSpacing

                Repeater {
                    model: chord.modelData
                    delegate: Rectangle {
                        id: cap
                        required property string modelData
                        height: priv.capHeight
                        width: Math.max(height, label.implicitWidth + Kirigami.Units.largeSpacing * 2)
                        radius: 6
                        color: Qt.alpha(Kirigami.Theme.textColor, 0.06)
                        border.width: 1
                        border.color: Qt.alpha(Kirigami.Theme.textColor, 0.18)

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: cap.modelData
                            color: Kirigami.Theme.textColor
                            font: Kirigami.Theme.smallFont
                            textFormat: Text.PlainText
                            Accessible.ignored: true
                        }
                    }
                }
            }
        }
    }
}
