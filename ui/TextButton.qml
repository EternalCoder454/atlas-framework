import QtQuick
import QtQuick.Templates as T
import org.kde.kirigami as Kirigami

// Link-styled button: accent text, no fill.
T.AbstractButton {
    id: control

    implicitWidth: label.implicitWidth + leftPadding + rightPadding
    implicitHeight: Math.max(TelamonStyle.controlHeight, label.implicitHeight + TelamonStyle.spacingSmall * 2)
    leftPadding: TelamonStyle.spacingSmall
    rightPadding: leftPadding
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: control.text
    Keys.onReturnPressed: event => {
        if (enabled && !event.isAutoRepeat) {
            control.click();
        }
    }
    Keys.onEnterPressed: event => {
        if (enabled && !event.isAutoRepeat) {
            control.click();
        }
    }

    contentItem: Text {
        id: label
        Accessible.ignored: true
        verticalAlignment: Text.AlignVCenter
        text: control.text
        font.family: TelamonStyle.fontFamily
        font.pointSize: TelamonStyle.fontSizeBody
        textFormat: Text.PlainText
        color: control.enabled ? TelamonStyle.accent : TelamonStyle.textDisabled
        Behavior on color {
            ColorAnimation {
                duration: TelamonStyle.durationShort
            }
        }
    }
    background: Rectangle {
        radius: TelamonStyle.radiusSmall
        // Grey hover and press, never the accent.
        color: !control.enabled ? "transparent" : control.down ? TelamonStyle.pressed : control.hovered ? TelamonStyle.hover : "transparent"
        Behavior on color {
            ColorAnimation {
                duration: TelamonStyle.durationShort
            }
        }
        TelamonFocusRing {
            radius: parent.radius + gap
            shown: control.visualFocus
        }
    }
}
