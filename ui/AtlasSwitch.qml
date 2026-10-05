import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Pill switch: accent track when on, white knob.
T.Switch {
    id: control

    implicitWidth: 40
    implicitHeight: 24
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    // The label beside the switch is the app's: name it with `text` or Accessible.name.
    Accessible.name: control.text
    // Screen readers say "switch, on" rather than "check box, checked".
    Accessible.role: Accessible.Switch

    indicator: Rectangle {
        implicitWidth: 40
        implicitHeight: 24
        x: control.leftPadding
        y: Math.round((control.height - height) / 2)
        radius: AtlasStyle.radiusPill
        // A disabled item gets Kirigami's Disabled colours, whose highlight
        // is near the background: a held switch that is on would look off.
        // The palette's active group keeps the accent; the fade below says
        // it's held.
        color: control.checked ? (control.enabled ? AtlasStyle.accent : control.palette.active.highlight) : Qt.alpha(Kirigami.Theme.textColor, control.hovered ? 0.28 : 0.2)
        border.width: control.visualFocus ? 2 : 0
        border.color: Qt.alpha(AtlasStyle.focus, 0.85)
        opacity: control.enabled ? 1 : 0.45
        Behavior on color {
            ColorAnimation {
                duration: AtlasStyle.durationShort
            }
        }
        Rectangle {
            width: 20
            height: 20
            radius: height / 2
            y: 2
            x: (control.checked !== control.mirrored) ? parent.width - width - 2 : 2
            color: "white"
            Behavior on x {
                NumberAnimation {
                    duration: AtlasStyle.durationShort
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
    contentItem: Item {}
}
