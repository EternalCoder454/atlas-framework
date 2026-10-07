pragma ComponentBehavior: Bound
import QtQuick
import org.kde.kirigami as Kirigami

// A keyboard shortcut drawn as keycaps, one per key, in the platform's own
// spelling. `sequence` is a string ("Ctrl+Shift+S") or a StandardKey number
// (`StandardKey.Save`), such as a TelamonAction's `shortcut`. A shortcut of
// several steps ("Ctrl+K, Ctrl+C") shows the steps one after the other with a
// comma between them, as the native text spells it. With
// no sequence it has no size. Screen readers get the sequence as text.
//
//   TelamonShortcutLabel { sequence: "Ctrl+Shift+S" }
//   TelamonShortcutLabel { sequence: saveAction.shortcut }
Item {
    id: control

    property var sequence: ""

    QtObject {
        id: priv
        readonly property string readableText: TelamonShortcuts.readable(control.sequence)
        readonly property var chords: TelamonShortcuts.keys(control.sequence)
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
        spacing: TelamonStyle.spacingSmall

        Repeater {
            model: priv.chords
            delegate: Row {
                id: chord
                required property var modelData
                required property int index
                spacing: TelamonStyle.spacingSmall

                Repeater {
                    model: chord.modelData
                    delegate: Rectangle {
                        id: cap
                        required property string modelData
                        height: priv.capHeight
                        width: Math.max(height, label.implicitWidth + TelamonStyle.spacingLarge * 2)
                        radius: TelamonStyle.radiusSmall
                        color: TelamonStyle.hover
                        border.width: 1
                        border.color: TelamonStyle.controlBorder

                        Text {
                            id: label
                            anchors.centerIn: parent
                            text: cap.modelData
                            color: TelamonStyle.text
                            font.family: TelamonStyle.fontFamily
                            font.pointSize: TelamonStyle.fontSizeCaption
                            textFormat: Text.PlainText
                            Accessible.ignored: true
                        }
                    }
                }

                // The separator after every step but the last: "Ctrl+K, Ctrl+C".
                // It sits in the step's Row, so it mirrors with the caps.
                Text {
                    visible: chord.index < priv.chords.length - 1
                    height: priv.capHeight
                    verticalAlignment: Text.AlignVCenter
                    text: ","
                    color: TelamonStyle.textMuted
                    font.family: TelamonStyle.fontFamily
                    font.pointSize: TelamonStyle.fontSizeCaption
                    textFormat: Text.PlainText
                    Accessible.ignored: true
                }
            }
        }
    }
}
