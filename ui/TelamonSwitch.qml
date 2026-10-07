import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Pill switch: accent track when on, and a knob that slides across with a small
// overshoot (not under reduced motion). Off shows a visible edge, also disabled.
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
        // At the right end when mirrored, also in a wide switch.
        x: control.mirrored ? control.width - width - control.rightPadding : control.leftPadding
        y: Math.round((control.height - height) / 2)
        // The track stays a pill.
        radius: TelamonStyle.radiusPill
        // Off: the control fill with a visible edge, so an off switch (also a
        // disabled one) can be seen on any surface. On: the accent, dimmed
        // when disabled (a disabled item's own palette would hide it).
        color: control.checked ? (control.enabled ? TelamonStyle.accent : TelamonStyle.alpha(TelamonStyle.accent, 0.4)) : control.enabled && control.hovered ? Qt.tint(TelamonStyle.control, TelamonStyle.hover) : TelamonStyle.control
        border.width: control.checked ? 0 : 1
        border.color: TelamonStyle.controlBorder
        Behavior on color {
            ColorAnimation {
                duration: TelamonStyle.durationShort
            }
        }
        Rectangle {
            id: thumb
            width: 20
            height: 20
            radius: height / 2
            y: 2
            x: (control.checked !== control.mirrored) ? parent.width - width - 2 : 2
            color: !control.enabled ? (control.checked ? TelamonStyle.accentText : TelamonStyle.textDisabled) : control.checked ? TelamonStyle.accentText : TelamonStyle.textMuted
            // The thumb slides with a small overshoot.
            Behavior on x {
                enabled: !TelamonStyle.reducedMotion
                TelamonSpringAnimation {
                    expressive: true
                }
            }
            Behavior on color {
                ColorAnimation {
                    duration: TelamonStyle.durationShort
                }
            }
        }
        TelamonFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }
    contentItem: Item {}
}
